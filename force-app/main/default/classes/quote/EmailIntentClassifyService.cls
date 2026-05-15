/**
 * EmailIntentClassifyService — 응답 메일 의도 자동 분류 (FR-QUOTE-007).
 *
 * 흐름:
 *   1) EmailMessageTrigger(after insert)가 Incoming + RelatedTo(Quote|Opp) 메일을 모음
 *   2) classifyAsync(List<Id>)을 @future(callout=true)로 호출
 *   3) 각 EmailMessage에 대해 IntentClassify Prompt Template 호출 → Intent__c 갱신
 *   4) 후속 자동 재견적 초안(FR-QUOTE-009)은 QuoteRequoteService.autoDraftIfRequote가 같은 비동기 전이에서 수행
 *
 * 6 카테고리 (EmailMessage.Intent__c picklist API value):
 *   Requote / Confirm / Reject / Conditions / Schedule / Other
 *
 * @group Quote
 */
public with sharing class EmailIntentClassifyService {

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'IntentClassify';
    @TestVisible private static final String CAPABILITY        = '';
    @TestVisible private static final String APPLICATION_NAME  = 'PromptBuilderPreview';

    private static final Set<String> VALID_INTENTS = new Set<String>{
        'Requote', 'Confirm', 'Reject', 'Conditions', 'Schedule', 'Other'
    };

    /** 테스트에서 LLM 응답 흉내. null이면 사용 안 됨. */
    @TestVisible private static String mockJsonResponse;
    /** 테스트에서 LLM 호출 실패 흉내. null이면 사용 안 됨. */
    @TestVisible private static String mockExceptionMessage;
    /** 트리거→@future 체인에서 RequoteDraft 후속 호출 건너뛰기 (단위테스트용). */
    @TestVisible private static Boolean suppressAutoRequote = false;

    /**
     * 비동기 진입점 — 트리거에서 호출.
     * @future(callout=true)로 LLM 호출 + Intent__c update.
     * 후속 RequoteDraft도 같은 호출 안에서 수행 (단일 @future로 단순화).
     */
    @future(callout=true)
    public static void classifyAsync(List<Id> emailMessageIds) {
        if (emailMessageIds == null || emailMessageIds.isEmpty()) return;
        for (Id emId : emailMessageIds) {
            try {
                classifyOne(emId);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'EmailIntentClassify failed for ' + emId + ': ' + e.getMessage());
            }
        }
        if (!suppressAutoRequote) {
            try {
                QuoteRequoteService.autoDraftIfRequote(emailMessageIds);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'QuoteRequote auto-draft failed: ' + e.getMessage());
            }
        }
    }

    /**
     * 동기 분류 — LWC 수동 분류 / 단위 테스트 / 백필 스크립트에서 호출.
     */
    @AuraEnabled
    public static ClassifyResult classifyOne(Id emailMessageId) {
        if (emailMessageId == null) throw newAura('emailMessageId is required');

        EmailMessage em = [
            SELECT Id, Subject, TextBody, Incoming, RelatedToId, Intent__c
            FROM EmailMessage
            WHERE Id = :emailMessageId
            LIMIT 1
        ];

        String aiJson;
        try {
            aiJson = invokePromptForEmail(em.Id);
        } catch (Exception e) {
            ClassifyResult err = new ClassifyResult();
            err.success = false;
            err.aiError = e.getMessage();
            return err;
        }

        ClassifyResult out = parseAndApply(em, aiJson);
        return out;
    }

    private static ClassifyResult parseAndApply(EmailMessage em, String aiJson) {
        ClassifyResult r = new ClassifyResult();
        r.emailMessageId = em.Id;
        r.aiJson = aiJson;

        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(stripCodeFences(aiJson));
        } catch (Exception e) {
            r.success = false;
            r.aiError = 'JSON parse error: ' + e.getMessage();
            return r;
        }

        String intent = String.valueOf(raw.get('intent'));
        if (!VALID_INTENTS.contains(intent)) {
            r.success = false;
            r.aiError = 'Unrecognized intent: ' + intent;
            return r;
        }
        r.intent     = intent;
        r.rationale  = String.valueOf(raw.get('rationale'));
        r.summary    = String.valueOf(raw.get('summary'));
        Object conf  = raw.get('confidence');
        r.confidence = (conf instanceof Decimal || conf instanceof Double || conf instanceof Integer)
                       ? Decimal.valueOf(String.valueOf(conf)) : null;

        em.Intent__c = intent;
        try {
            update em;
            r.success = true;
        } catch (DmlException e) {
            r.success = false;
            r.aiError = 'Intent__c update failed: ' + e.getDmlMessage(0);
        }
        return r;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Prompt Builder 호출 (Day 5 OCR / Day 7 OppInsight 패턴)
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static String invokePromptForEmail(Id emailMessageId) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new IntentException(mockExceptionMessage);
            return mockJsonResponse != null
                ? mockJsonResponse
                : '{"intent":"Other","confidence":0.5,"rationale":"테스트 기본","summary":"테스트 메일"}';
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = new Map<String, Object>{ 'Id' => emailMessageId };
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:EmailRecord' => wv
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);

        if (resp == null) throw new IntentException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new IntentException('LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new IntentException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    /**
     * LLM이 응답을 ```json ... ``` 같은 마크다운 코드 펜스로 감싸는 경우 제거.
     * 프롬프트로 막아도 모델이 종종 무시하므로 파서 측 방어가 필요.
     */
    @TestVisible
    private static String stripCodeFences(String body) {
        if (String.isBlank(body)) return body;
        String trimmed = body.trim();
        if (!trimmed.startsWith('`')) return trimmed;
        Pattern p = Pattern.compile('(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$');
        Matcher m = p.matcher(trimmed);
        return m.matches() ? m.group(1) : trimmed;
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    public class ClassifyResult {
        @AuraEnabled public Id      emailMessageId;
        @AuraEnabled public String  intent;        // Requote / Confirm / Reject / Conditions / Schedule / Other
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String  rationale;
        @AuraEnabled public String  summary;
        @AuraEnabled public String  aiJson;
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String  aiError;
    }

    public class IntentException extends Exception {}
}
