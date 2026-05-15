/**
 * @description LWC `bcUploadCard`의 Apex 진입점. 명함 업로드를 받아 BusinessCard 레코드를
 *              만들고 비동기 LLM 분석을 트리거한 뒤, 결과 회수까지의 흐름을 관장한다.
 *
 * @group AutoLeadByBC
 *
 * <h3>비동기 처리 흐름 (F-Async)</h3>
 * <ol>
 *   <li>LWC가 base64 이미지로 {@link enqueueProcessing}(fileName, base64) 호출.</li>
 *   <li>이 메서드가 ContentVersion INSERT → BusinessCard__c (Status='Queued') INSERT
 *       → ContentDocumentLink 생성 → BC_ProcessQueueable.enqueueJob → 즉시 businessCardId 반환.</li>
 *   <li>Queueable이 백그라운드에서 {@link processInBackground} 호출 (LLM, 매핑, Lead 생성, Status 업데이트).</li>
 *   <li>LWC는 폴링하여 Status가 'LeadCreated' / 'Failed'로 바뀌면 {@link fetchResult}로 결과 회수.</li>
 * </ol>
 *
 * <h3>책임 경계</h3>
 * <ul>
 *   <li>매핑은 {@link BC_FieldMapper}에 위임</li>
 *   <li>DML은 {@link BC_RecordWriter}에 위임</li>
 *   <li>중복검사는 {@link BC_DuplicateChecker}에 위임</li>
 *   <li>LLM 호출은 {@link BC_PromptInvoker}에 위임</li>
 * </ul>
 *
 * @see BC_ProcessQueueable
 * @see bcUploadCard (LWC)
 */
public with sharing class AutoLeadByBC_Service {

    @TestVisible private static IBC_PromptInvoker   invoker = new BC_PromptInvoker();
    @TestVisible private static BC_FieldMapper      mapper  = new BC_FieldMapper();
    @TestVisible private static BC_RecordWriter     writer  = new BC_RecordWriter();
    @TestVisible private static BC_DuplicateChecker checker = new BC_DuplicateChecker();
    /** @description 테스트에서 enqueueJob 호출을 우회하기 위한 플래그. */
    @TestVisible private static Boolean skipQueueable = false;

    /**
     * @description LWC 진입점 — 파일 업로드 + 비동기 처리 시작.
     *              동기 단계만 빠르게 끝낸 뒤 즉시 ResultDTO(status='Queued')를 반환한다.
     *
     * @param fileName    업로드 원본 파일명 (예: "image.jpg"). 빈 값이면 INVALID_INPUT 실패.
     * @param base64Image 클라이언트에서 전처리한 이미지의 base64 문자열. 빈 값이면 INVALID_INPUT 실패.
     * @return 즉시 반환되는 ResultDTO. status='Queued', businessCardId가 채워져 있다.
     *         실패 시 status='Failed', failureCode/failureMessage가 채워진다.
     *
     * @example
     * AutoLeadByBC_Service.ResultDTO dto =
     *     AutoLeadByBC_Service.enqueueProcessing('card.jpg', base64Str);
     * // dto.businessCardId 로 LWC가 폴링 시작
     */
    @AuraEnabled
    public static ResultDTO enqueueProcessing(String fileName, String base64Image) {
        if (String.isBlank(fileName) || String.isBlank(base64Image)) {
            return failureWithoutCard('INVALID_INPUT', 'fileName과 base64Image는 필수입니다');
        }

        // 1. ContentVersion INSERT (전처리된 이미지)
        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = EncodingUtil.base64Decode(base64Image)
        );
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        // 2. BusinessCard 생성 (Status='Queued')
        BusinessCard__c card = writer.insertExtracting();
        card.Status__c = 'Queued';
        update card;

        // 3. ContentDocumentLink: BusinessCard ↔ Image
        try {
            writer.linkContentDocument(card.Id, cdId);
        } catch (Exception e) {
            writer.markFailed(card, 'INVALID_INPUT',
                'ContentDocumentLink 실패: ' + e.getMessage(), 0);
            return failureWithCard(card.Id, 'INVALID_INPUT', e.getMessage());
        }

        // 4. Queueable enqueue (테스트 환경에서는 skip 가능)
        if (!skipQueueable) {
            System.enqueueJob(new BC_ProcessQueueable(card.Id, cdId));
        }

        // 5. 즉시 반환
        ResultDTO dto = new ResultDTO();
        dto.businessCardId = card.Id;
        dto.status = 'Queued';
        return dto;
    }

    /**
     * @description Queueable.execute에서 호출되는 비동기 본 처리. (테스트에서 직접 호출도 가능)
     *              Status를 'LeadCreated' 또는 'Failed'로 마치고, ContentDocumentLink을 Lead에도 추가한다.
     *
     * @param businessCardId    Status='Queued' 상태로 미리 저장된 BusinessCard__c의 Id.
     * @param contentDocumentId BusinessCard에 연결된 명함 이미지의 ContentDocument Id.
     */
    public static void processInBackground(Id businessCardId, Id contentDocumentId) {
        Long t0 = System.currentTimeMillis();

        BusinessCard__c card = [
            SELECT Id, Status__c FROM BusinessCard__c WHERE Id = :businessCardId LIMIT 1
        ];

        BC_LLMResponse resp;
        try {
            resp = invoker.invokeForImage(contentDocumentId);
        } catch (Exception e) {
            writer.markFailed(card, 'LLM_FAILURE', e.getMessage(), elapsed(t0));
            return;
        }

        if (resp == null || resp.isBusinessCard != true) {
            card.Raw_OCR_Text__c = (resp != null) ? resp.rawText : null;
            writer.markFailed(card, 'NOT_BUSINESS_CARD', '명함이 아닙니다', elapsed(t0));
            return;
        }

        mapper.applyExtraction(card, resp);
        writer.updateMapped(card);

        Lead lead;
        List<Id> matchedIds = new List<Id>();
        try {
            lead = mapper.buildLead(card);
            matchedIds = checker.findMatchedIds(lead);
            if (matchedIds != null && !matchedIds.isEmpty()) {
                lead.Duplicate_Suspect__c = true;
                lead.Duplicate_Suspect_Info__c = String.join(matchedIds, ', ');
            }
            writer.insertLeadAllowingDuplicates(lead);
        } catch (Exception e) {
            writer.markFailed(card, 'DML_FAILURE', 'Lead 생성 실패: ' + e.getMessage(), elapsed(t0));
            return;
        }

        writer.markLeadCreated(card, lead.Id, elapsed(t0));

        try {
            writer.linkContentDocumentToLead(lead.Id, contentDocumentId);
        } catch (Exception ignored) { /* 보조 링크 — 실패해도 본 흐름 영향 없음 */ }
    }

    /**
     * @description LWC가 BusinessCard.Status 변화 감지 시 호출. 'LeadCreated' 또는 'Failed' 결과를 반환.
     *
     * @param businessCardId 회수할 BusinessCard__c의 Id. null이면 INVALID_INPUT 실패.
     * @return ResultDTO. status='LeadCreated' 시 leadId/company/lastName/title 등이 채워지고,
     *                    status='Failed' 시 failureCode/failureMessage가 채워진다.
     *
     * @example
     * AutoLeadByBC_Service.ResultDTO dto =
     *     AutoLeadByBC_Service.fetchResult(businessCardId);
     */
    @AuraEnabled
    public static ResultDTO fetchResult(Id businessCardId) {
        if (businessCardId == null) {
            return failureWithoutCard('INVALID_INPUT', 'businessCardId required');
        }

        BusinessCard__c card = [
            SELECT Id, Status__c, Lead__c, Company__c, Last_Name__c, Title__c,
                   Detected_Language__c, Extraction_Warnings__c,
                   Extraction_Confidence_JSON__c, Failure_Reason__c, Processing_Duration_Ms__c
            FROM BusinessCard__c WHERE Id = :businessCardId LIMIT 1
        ];

        ResultDTO dto = new ResultDTO();
        dto.businessCardId = card.Id;
        dto.status = card.Status__c;
        dto.durationMs = card.Processing_Duration_Ms__c;
        dto.detectedLanguage = card.Detected_Language__c;

        if (card.Status__c == 'LeadCreated' && card.Lead__c != null) {
            dto.leadId = card.Lead__c;
            dto.company = card.Company__c;
            dto.lastName = card.Last_Name__c;
            dto.title = card.Title__c;
            populateDuplicateInfo(dto, card.Lead__c);
            populateMissingFields(dto, card.Extraction_Confidence_JSON__c);
            populateWarnings(dto, card.Extraction_Warnings__c);
        } else if (card.Status__c == 'Failed') {
            dto.failureMessage = card.Failure_Reason__c;
            dto.failureCode = parseFailureCode(card.Failure_Reason__c);
        }
        return dto;
    }

    // ---------------------------- helpers ----------------------------

    /**
     * @description 시작 시각 t0부터 현재까지 경과 ms.
     * @param t0 시작 시각 (ms)
     * @return 경과 ms
     */
    private static Long elapsed(Long t0) {
        return System.currentTimeMillis() - t0;
    }

    private static ResultDTO failureWithoutCard(String code, String msg) {
        ResultDTO dto = new ResultDTO();
        dto.status = 'Failed';
        dto.failureCode = code;
        dto.failureMessage = msg;
        return dto;
    }

    private static ResultDTO failureWithCard(Id cardId, String code, String msg) {
        ResultDTO dto = new ResultDTO();
        dto.businessCardId = cardId;
        dto.status = 'Failed';
        dto.failureCode = code;
        dto.failureMessage = msg;
        return dto;
    }

    /**
     * @description Failure_Reason__c가 "[CODE] message" 형식일 때 CODE만 추출.
     * @param reason Failure_Reason__c 원문
     * @return 대괄호 내부 코드 또는 null
     */
    private static String parseFailureCode(String reason) {
        if (String.isBlank(reason) || !reason.startsWith('[')) return null;
        Integer endIdx = reason.indexOf(']');
        return (endIdx > 0) ? reason.substring(1, endIdx) : null;
    }

    private static void populateDuplicateInfo(ResultDTO dto, Id leadId) {
        Lead lead = [SELECT Duplicate_Suspect__c, Duplicate_Suspect_Info__c FROM Lead WHERE Id = :leadId LIMIT 1];
        if (lead.Duplicate_Suspect__c == true && String.isNotBlank(lead.Duplicate_Suspect_Info__c)) {
            for (String id : lead.Duplicate_Suspect_Info__c.split(',\\s*')) {
                if (String.isNotBlank(id)) dto.duplicateMatchedIds.add(id.trim());
            }
            dto.duplicateCount = dto.duplicateMatchedIds.size();
        }
    }

    private static void populateMissingFields(ResultDTO dto, String confJson) {
        if (String.isBlank(confJson)) return;
        Map<String, Object> conf;
        try {
            conf = (Map<String, Object>) JSON.deserializeUntyped(confJson);
        } catch (Exception e) { return; }
        for (String k : conf.keySet()) {
            Object v = conf.get(k);
            if (v instanceof Decimal && ((Decimal) v) < 0.5) {
                dto.missingFields.add(k);
            } else if (v instanceof Integer && ((Integer) v) < 1) {
                dto.missingFields.add(k);
            }
        }
    }

    private static void populateWarnings(ResultDTO dto, String warningsField) {
        if (String.isBlank(warningsField)) return;
        for (String w : warningsField.split('\n')) {
            if (String.isNotBlank(w)) dto.warnings.add(w);
        }
    }

    /**
     * @description LWC `bcUploadCard`에 반환할 처리 결과 객체.
     *              모든 필드는 @AuraEnabled로 LWC에서 직접 사용 가능.
     */
    public class ResultDTO {
        /** @description 생성된 BusinessCard__c의 Id. enqueueProcessing 직후부터 채워진다. */
        @AuraEnabled public Id businessCardId;
        /** @description 처리 완료된 Lead의 Id. status='LeadCreated'일 때만 채워진다. */
        @AuraEnabled public Id leadId;
        /** @description Queued | Mapped | LeadCreated | Failed */
        @AuraEnabled public String status;
        /** @description confidence < 0.5인 필드명 목록 (예: ['website','title']). UI 표시용. */
        @AuraEnabled public List<String> missingFields = new List<String>();
        /** @description LLM이 보낸 한국어 경고 메시지 목록. */
        @AuraEnabled public List<String> warnings = new List<String>();
        /** @description 실패 분류 코드: INVALID_INPUT | LLM_FAILURE | NOT_BUSINESS_CARD | DML_FAILURE */
        @AuraEnabled public String failureCode;
        /** @description 사용자 표시용 실패 메시지 (코드 prefix 제외). */
        @AuraEnabled public String failureMessage;
        /** @description 인큐 → 결과 마감까지의 총 경과 (ms). */
        @AuraEnabled public Decimal durationMs;
        /** @description LLM이 감지한 언어 (예: 'ko', 'en'). */
        @AuraEnabled public String detectedLanguage;
        @AuraEnabled public String company;
        @AuraEnabled public String lastName;
        @AuraEnabled public String title;
        /** @description 표준 Duplicate Rule 매칭 건수. 0이면 중복 없음. */
        @AuraEnabled public Integer duplicateCount = 0;
        /** @description 매칭된 기존 Lead Id 목록. */
        @AuraEnabled public List<String> duplicateMatchedIds = new List<String>();
    }
}
