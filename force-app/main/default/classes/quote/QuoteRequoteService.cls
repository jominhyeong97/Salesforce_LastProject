/**
 * QuoteRequoteService — 재견적 의도(Intent='Requote') 회신 메일 → 새 Quote 초안 자동 작성.
 *
 * 안전 우선 정책:
 *   - 라인 가격은 AI가 직접 갱신하지 않음(price tampering risk). 라인은 원본을 그대로 복제.
 *   - AI 제안은 Quote.Description 에 한국어 자연어로 기록 + AI_Draft_Confidence__c 에 신뢰도 저장.
 *   - AE가 quoteBuilder 에서 제안을 보고 수동으로 라인 편집(D15 — AE 부담만 감축, 결정권 AE).
 *
 * Fallback:
 *   - LLM 호출 실패 시 AI 요약 없이 단순 복제 + Description 에 "AI 분석 실패 — 수동 검토" 메시지.
 *
 * @group Quote
 */
public with sharing class QuoteRequoteService {

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'RequoteDraft';
    @TestVisible private static final String CAPABILITY        = '';
    @TestVisible private static final String APPLICATION_NAME  = 'PromptBuilderPreview';

    @TestVisible private static String mockJsonResponse;
    @TestVisible private static String mockExceptionMessage;

    /**
     * 트리거 @future 체인에서 호출 — Intent='Requote' 인 메일만 골라 새 견적 초안 작성.
     */
    public static void autoDraftIfRequote(List<Id> emailMessageIds) {
        if (emailMessageIds == null || emailMessageIds.isEmpty()) return;
        List<EmailMessage> ems = [
            SELECT Id, Intent__c, RelatedToId
            FROM EmailMessage
            WHERE Id IN :emailMessageIds AND Intent__c = 'Requote'
        ];
        for (EmailMessage em : ems) {
            try {
                draftFromEmailMessage(em.Id);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'QuoteRequote draft failed for ' + em.Id + ': ' + e.getMessage());
            }
        }
    }

    /**
     * LWC 수동 트리거(예: emailIntentBadge 의 "재견적 초안 생성" 버튼)에서 호출.
     */
    @AuraEnabled
    public static DraftResult draftFromEmail(Id emailMessageId) {
        if (emailMessageId == null) throw newAura('emailMessageId is required');
        return draftFromEmailMessage(emailMessageId);
    }

    // ─────────────────────────────────────────────────────────────────────
    // 내부 — 1건 draft 작성
    // ─────────────────────────────────────────────────────────────────────

    private static DraftResult draftFromEmailMessage(Id emailMessageId) {
        DraftResult r = new DraftResult();
        r.sourceEmailId = emailMessageId;

        EmailMessage em = [
            SELECT Id, Intent__c, RelatedToId, Subject, TextBody
            FROM EmailMessage WHERE Id = :emailMessageId LIMIT 1
        ];

        Id originalQuoteId = resolveQuoteId(em);
        if (originalQuoteId == null) {
            r.aiError = '연결된 Quote 를 찾지 못했습니다 (RelatedToId 확인).';
            return r;
        }
        r.originalQuoteId = originalQuoteId;

        Quote original = loadQuoteWithLines(originalQuoteId);

        AiResponse ai;
        try {
            String aiJson = invokePrompt(originalQuoteId, em.Id);
            r.aiJson = aiJson;
            ai = parseAi(aiJson);
            r.aiSource = 'ai';
        } catch (Exception e) {
            ai = buildFallback();
            r.aiError  = e.getMessage();
            r.aiSource = 'fallback';
        }
        r.aiSummary       = ai.summary;
        r.aiConfidence    = ai.confidence;
        r.expirationDays  = ai.expirationDays;

        Quote draft = buildDraftQuote(original, ai);
        insert draft;
        r.draftQuoteId = draft.Id;

        List<QuoteLineItem> draftLines = cloneLines(original, draft.Id);
        if (!draftLines.isEmpty()) insert draftLines;
        r.lineCount = draftLines.size();
        r.success = true;
        return r;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Quote / Line 복제
    // ─────────────────────────────────────────────────────────────────────

    private static Quote loadQuoteWithLines(Id quoteId) {
        return [
            SELECT Id, Name, OpportunityId, AccountId, Pricebook2Id, ContactId,
                   Description, Status, ExpirationDate, TotalPrice,
                   (SELECT Id, PricebookEntryId, Product2Id, Quantity, UnitPrice,
                           Discount_Amount__c, Description, ServiceDate
                    FROM QuoteLineItems)
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];
    }

    private static Quote buildDraftQuote(Quote src, AiResponse ai) {
        Quote q = new Quote();
        q.OpportunityId   = src.OpportunityId;
        q.Pricebook2Id    = src.Pricebook2Id;
        q.ContactId       = src.ContactId;
        q.Name            = (src.Name != null ? src.Name : 'Quote') + ' (재견적)';
        q.Status          = '초안';
        q.ExpirationDate  = Date.today().addDays(
            ai.expirationDays != null && ai.expirationDays > 0 ? ai.expirationDays : 14);

        String aiBlock = '[AI 재견적 분석]\n' +
            '신뢰도: ' + (ai.confidence != null ? ai.confidence.setScale(2).toPlainString() : 'n/a') + '\n' +
            (String.isNotBlank(ai.summary) ? ai.summary : '— 요약 없음') + '\n' +
            (ai.lineAdjustments != null && !ai.lineAdjustments.isEmpty()
                ? '\n[제안 조정안]\n' + renderAdjustments(ai.lineAdjustments)
                : '');
        q.Description = aiBlock.left(31000);
        q.AI_Draft_Confidence__c = (ai.confidence != null) ? ai.confidence : 0.0;
        q.AE_Edit_Count__c = 0;
        return q;
    }

    private static List<QuoteLineItem> cloneLines(Quote src, Id newQuoteId) {
        List<QuoteLineItem> out = new List<QuoteLineItem>();
        if (src.QuoteLineItems == null) return out;
        for (QuoteLineItem qli : src.QuoteLineItems) {
            QuoteLineItem nq = new QuoteLineItem();
            nq.QuoteId           = newQuoteId;
            nq.PricebookEntryId  = qli.PricebookEntryId;
            nq.Quantity          = qli.Quantity;
            nq.UnitPrice         = qli.UnitPrice;
            nq.Discount_Amount__c = qli.Discount_Amount__c;
            nq.Description       = qli.Description;
            nq.ServiceDate       = qli.ServiceDate;
            out.add(nq);
        }
        return out;
    }

    private static String renderAdjustments(List<LineAdjustment> adjs) {
        List<String> lines = new List<String>();
        for (LineAdjustment a : adjs) {
            String pc = String.isNotBlank(a.productCode) ? a.productCode : '(전체)';
            String val = (a.suggestedValue != null) ? a.suggestedValue.toString() : '';
            String why = String.isNotBlank(a.rationale) ? ' — ' + a.rationale : '';
            lines.add('• ' + pc + ' / ' + a.changeType + ' = ' + val + why);
        }
        return String.join(lines, '\n');
    }

    private static Id resolveQuoteId(EmailMessage em) {
        if (em.RelatedToId == null) return null;
        String t = em.RelatedToId.getSObjectType().getDescribe().getName();
        if (t == 'Quote') return em.RelatedToId;
        if (t == 'Opportunity') {
            List<Quote> qs = [
                SELECT Id FROM Quote
                WHERE OpportunityId = :em.RelatedToId AND Status IN ('발송', '응답대기')
                ORDER BY Sent_Date__c DESC NULLS LAST, LastModifiedDate DESC
                LIMIT 1
            ];
            return qs.isEmpty() ? null : qs[0].Id;
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Prompt Builder 호출
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static String invokePrompt(Id quoteId, Id emailMessageId) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new RequoteException(mockExceptionMessage);
            return mockJsonResponse != null
                ? mockJsonResponse
                : '{"summary":"테스트 재견적 요약","confidence":0.8,"expirationDays":14,"lineAdjustments":[]}';
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue qv = new ConnectApi.WrappedValue();
        qv.value = new Map<String, Object>{ 'Id' => quoteId };
        ConnectApi.WrappedValue ev = new ConnectApi.WrappedValue();
        ev.value = new Map<String, Object>{ 'Id' => emailMessageId };
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:QuoteRecord' => qv,
            'Input:EmailRecord' => ev
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);

        if (resp == null) throw new RequoteException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new RequoteException('LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new RequoteException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    private static AiResponse parseAi(String body) {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(stripCodeFences(body));
        AiResponse a = new AiResponse();
        a.summary    = String.valueOf(raw.get('summary'));
        a.confidence = decimalOf(raw.get('confidence'));
        a.expirationDays = (raw.get('expirationDays') != null)
            ? Integer.valueOf(String.valueOf(raw.get('expirationDays'))) : 14;
        a.lineAdjustments = new List<LineAdjustment>();
        Object arr = raw.get('lineAdjustments');
        if (arr instanceof List<Object>) {
            for (Object o : (List<Object>) arr) {
                if (!(o instanceof Map<String, Object>)) continue;
                Map<String, Object> m = (Map<String, Object>) o;
                LineAdjustment la = new LineAdjustment();
                la.productCode    = String.valueOf(m.get('productCode'));
                la.changeType     = String.valueOf(m.get('changeType'));
                la.suggestedValue = m.get('suggestedValue');
                la.rationale      = String.valueOf(m.get('rationale'));
                a.lineAdjustments.add(la);
            }
        }
        return a;
    }

    private static AiResponse buildFallback() {
        AiResponse a = new AiResponse();
        a.summary    = '재견적 요청 회신 감지. AI 분석은 실패했으니 AE 가 회신을 확인하고 라인을 수동 조정해 주세요.';
        a.confidence = 0.0;
        a.expirationDays = 14;
        a.lineAdjustments = new List<LineAdjustment>();
        return a;
    }

    /** LLM 응답이 ```json ... ``` 코드 펜스로 감싸진 경우 제거. */
    @TestVisible
    private static String stripCodeFences(String body) {
        if (String.isBlank(body)) return body;
        String trimmed = body.trim();
        if (!trimmed.startsWith('`')) return trimmed;
        Pattern p = Pattern.compile('(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$');
        Matcher m = p.matcher(trimmed);
        return m.matches() ? m.group(1) : trimmed;
    }

    private static Decimal decimalOf(Object o) {
        if (o == null) return null;
        try { return Decimal.valueOf(String.valueOf(o)); } catch (Exception e) { return null; }
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs
    // ─────────────────────────────────────────────────────────────────────

    public class DraftResult {
        @AuraEnabled public Id      sourceEmailId;
        @AuraEnabled public Id      originalQuoteId;
        @AuraEnabled public Id      draftQuoteId;
        @AuraEnabled public Integer lineCount;
        @AuraEnabled public String  aiSummary;
        @AuraEnabled public Decimal aiConfidence;
        @AuraEnabled public Integer expirationDays;
        @AuraEnabled public String  aiJson;
        @AuraEnabled public String  aiSource;     // 'ai' | 'fallback'
        @AuraEnabled public String  aiError;
        @AuraEnabled public Boolean success = false;
    }

    public class AiResponse {
        public String summary;
        public Decimal confidence;
        public Integer expirationDays;
        public List<LineAdjustment> lineAdjustments;
    }

    public class LineAdjustment {
        public String productCode;
        public String changeType;     // discount | unitPrice | quantity | leadTime | note
        public Object suggestedValue;
        public String rationale;
    }

    public class RequoteException extends Exception {}
}
