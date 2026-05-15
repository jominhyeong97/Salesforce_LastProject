/**
 * BusinessLicensePromptService — 사업자등록증 OCR + Account 자동 보강 진입점.
 *
 * 동기 처리 흐름:
 *   1. recordId(Account|Opportunity) → accountId 결정
 *   2. ContentVersion + ContentDocumentLink 생성 (Account ↔ 파일)
 *   3. invokeForImage(contentDocumentId)
 *      → 3-arg ConnectApi 호출 + Input:ContentDocument WrappedValue 명시
 *   4. 응답 모든 필드 blank → status='extract_empty' + 별도 안내
 *   5. 그렇지 않으면 Account 4필드 보강 (null/blank skip)
 *   6. enriched.size() / skipped.size()로 success | partial 결정
 *
 * Status:
 *   success         — 4필드 모두 추출 + Account 보강
 *   partial         — 1~3필드 추출 + 부분 보강
 *   extract_empty   — 0필드 추출 (이미지 인식 실패) — Account 변경 없음
 *   error_ocr       — Prompt Builder 호출 자체 실패
 *   error_account   — Account 조회/업데이트 실패
 *   error_file      — 파일 저장 실패
 */
public with sharing class BusinessLicensePromptService {

    public static final String STATUS_SUCCESS         = 'success';
    public static final String STATUS_PARTIAL         = 'partial';
    public static final String STATUS_EXTRACT_EMPTY   = 'extract_empty';
    public static final String STATUS_ERROR_OCR       = 'error_ocr';
    public static final String STATUS_ERROR_ACCOUNT   = 'error_account';
    public static final String STATUS_ERROR_FILE      = 'error_file';

    @TestVisible private static final String TEMPLATE_DEV_NAME  = 'BusinessLicenseExtract';
    @TestVisible private static final String CAPABILITY         = '';
    @TestVisible private static final String APPLICATION_NAME   = 'PromptBuilderPreview';

    private static final String EXTRACT_EMPTY_MSG =
        '사업자등록증 내용을 인식하지 못했습니다. 이미지가 흐리거나 어둡지 않은지, ' +
        '사업자등록증 전체가 프레임에 들어왔는지, 정면에서 촬영했는지 확인해 주세요.';

    private static final String DEFAULT_TEST_JSON =
        '{"businessNumber":"","companyName":"","ceoName":"","address":"","raw_text":""}';

    /** 테스트에서 LLM 응답을 흉내내기 위한 mock JSON. null이면 사용 안 됨. */
    @TestVisible private static String mockJsonResponse;
    /** 테스트에서 LLM 호출 실패를 흉내내기 위한 예외 메시지. null이면 사용 안 됨. */
    @TestVisible private static String mockExceptionMessage;

    /**
     * LWC 진입점.
     * @param opportunityId  Account ID 또는 Opportunity ID (LWC의 recordId)
     * @param fileName       업로드 파일명 (예: "사업자등록증.jpg")
     * @param base64FileContent base64 인코딩 파일 콘텐츠
     * @return result Map (status, ocrJson, extracted, enrichedFields, partialFailures, contentDocumentId, errorMessage)
     */
    @AuraEnabled
    public static Map<String, Object> processLicense(
        Id opportunityId,
        String fileName,
        String base64FileContent
    ) {
        Map<String, Object> result = baseResult();

        // 1. recordId → accountId
        Id accountId;
        try {
            accountId = resolveAccountId(opportunityId);
        } catch (Exception e) {
            return failure(result, STATUS_ERROR_ACCOUNT,
                'Account 조회 실패: ' + e.getMessage());
        }
        if (accountId == null) {
            return failure(result, STATUS_ERROR_ACCOUNT,
                'Account를 찾을 수 없습니다. (recordId: ' + opportunityId + ')');
        }

        // 2. 파일 저장 (ContentVersion + ContentDocumentLink)
        Id contentDocumentId;
        try {
            contentDocumentId = saveLicenseFile(accountId, fileName, base64FileContent);
            result.put('contentDocumentId', contentDocumentId);
        } catch (Exception e) {
            return failure(result, STATUS_ERROR_FILE, '파일 저장 실패: ' + e.getMessage());
        }

        // 3. Prompt Builder 호출
        BusinessLicenseLLMResponse ocr;
        try {
            ocr = invokeForImage(contentDocumentId);
        } catch (Exception e) {
            return failure(result, STATUS_ERROR_OCR,
                'OCR 호출 실패: ' + e.getMessage());
        }

        result.put('ocrJson',   ocr.originalJson);
        result.put('extracted', ocr.asExtractedMap());

        // 4. 모든 필드 blank → 별도 status
        if (ocr.isAllBlank()) {
            result.put('status', STATUS_EXTRACT_EMPTY);
            result.put('errorMessage', EXTRACT_EMPTY_MSG);
            return result;
        }

        // 5. Account 보강
        List<String> enriched = new List<String>();
        List<String> skipped  = new List<String>();
        try {
            enrichAccount(accountId, ocr, enriched, skipped);
        } catch (Exception e) {
            return failure(result, STATUS_ERROR_ACCOUNT,
                'Account 업데이트 실패: ' + e.getMessage());
        }
        result.put('enrichedFields',  enriched);
        result.put('partialFailures', skipped);

        // 6. 최종 status
        if (skipped.isEmpty()) {
            result.put('status', STATUS_SUCCESS);
            result.put('errorMessage', '');
        } else {
            result.put('status', STATUS_PARTIAL);
            result.put('errorMessage',
                'OCR 부분 성공. 미추출 필드: ' + String.join(skipped, ', ') + ' — 수동 입력해 주세요.');
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Prompt Builder 호출 (3-arg ConnectApi + Input:ContentDocument WrappedValue)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * ContentDocument 1건을 입력으로 멀티모달 Prompt Template 호출.
     * 테스트 컨텍스트에서는 mockJsonResponse / mockExceptionMessage로 우회.
     */
    @TestVisible
    private static BusinessLicenseLLMResponse invokeForImage(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new BusinessLicensePromptException('contentDocumentId is required');
        }
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) {
                throw new BusinessLicensePromptException(mockExceptionMessage);
            }
            return BusinessLicenseLLMResponse.fromJson(
                mockJsonResponse != null ? mockJsonResponse : DEFAULT_TEST_JSON);
        }
        return BusinessLicenseLLMResponse.fromJson(callConnectApi(contentDocumentId));
    }

    private static String callConnectApi(Id contentDocumentId) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;
        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = new Map<String, Object>{ 'Id' => contentDocumentId };
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:ContentDocument' => wv
        };
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);
        if (resp == null) {
            throw new BusinessLicensePromptException('LLM returned null response');
        }
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new BusinessLicensePromptException(
                'LLM generation error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new BusinessLicensePromptException('LLM returned empty generations');
        }
        return resp.generations[0].text;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Account / 파일 / 결과 helpers
    // ─────────────────────────────────────────────────────────────────────

    private static Map<String, Object> baseResult() {
        return new Map<String, Object>{
            'status'             => STATUS_ERROR_OCR,
            'ocrJson'            => null,
            'extracted'          => new Map<String, String>(),
            'enrichedFields'     => new List<String>(),
            'partialFailures'    => new List<String>(),
            'contentDocumentId'  => null,
            'errorMessage'       => ''
        };
    }

    private static Map<String, Object> failure(Map<String, Object> result, String status, String message) {
        result.put('status', status);
        result.put('errorMessage', message);
        return result;
    }

    private static Id resolveAccountId(Id recordId) {
        if (recordId == null) return null;
        String objType = recordId.getSObjectType().getDescribe().getName();
        if (objType == 'Account') return recordId;
        if (objType == 'Opportunity') {
            Opportunity opp = [SELECT AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1];
            return opp.AccountId;
        }
        return null;
    }

    @TestVisible
    private static void enrichAccount(
        Id accountId,
        BusinessLicenseLLMResponse ocr,
        List<String> enriched,
        List<String> skipped
    ) {
        Account acc = [SELECT Id, Name, Business_Number__c, CEO_Name__c, BillingStreet
                       FROM Account WHERE Id = :accountId LIMIT 1];

        if (String.isNotBlank(ocr.businessNumber)) {
            acc.Business_Number__c = ocr.businessNumber;
            enriched.add('businessNumber');
        } else { skipped.add('businessNumber'); }

        if (String.isNotBlank(ocr.companyName)) {
            acc.Name = ocr.companyName;
            enriched.add('companyName');
        } else { skipped.add('companyName'); }

        if (String.isNotBlank(ocr.ceoName)) {
            acc.CEO_Name__c = ocr.ceoName;
            enriched.add('ceoName');
        } else { skipped.add('ceoName'); }

        if (String.isNotBlank(ocr.address)) {
            acc.BillingStreet = ocr.address;
            enriched.add('address');
        } else { skipped.add('address'); }

        if (!enriched.isEmpty()) {
            update acc;
        }
    }

    @TestVisible
    private static Id saveLicenseFile(Id accountId, String fileName, String base64) {
        ContentVersion cv = new ContentVersion(
            ContentLocation = 'S',
            PathOnClient    = fileName,
            Title           = '사업자등록증_' + Date.today().format(),
            VersionData     = EncodingUtil.base64Decode(base64)
        );
        insert cv;

        Id cdId = [SELECT ContentDocumentId FROM ContentVersion
                   WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cdId,
            LinkedEntityId    = accountId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdl;
        return cdId;
    }

    public class BusinessLicensePromptException extends Exception {}
}
