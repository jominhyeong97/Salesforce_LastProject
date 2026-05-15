/**
 * DraftFollowupEmailAction — Agentforce Action: Quote follow-up 메일 초안 작성.
 *
 * 발송 후 무응답이거나 응답이 늦은 Quote 에 대한 정중한 한국어 follow-up 메일을 자동 작성.
 * FollowupDraft Prompt Template (SOBJECT://Quote) 호출, 실패 시 한국어 fallback.
 *
 * 안전 정책 (D26 일관) — AI 는 가격/수량/할인 직접 변경 금지. 메일 본문만 생성.
 * 호출자는 stripCodeFences 헬퍼로 코드 펜스 제거 후 JSON 파싱.
 *
 * 사용 시점 — "○○ Quote follow-up", "재발송 메일", "응답 지연 알림" 같은 자연어 질의.
 *
 * @group Agentforce
 */
public with sharing class DraftFollowupEmailAction {

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'FollowupDraft';
    @TestVisible private static final String CAPABILITY        = '';
    @TestVisible private static final String APPLICATION_NAME  = 'PromptBuilderPreview';

    @TestVisible private static String mockAiResponse;
    @TestVisible private static String mockExceptionMessage;

    public class Request {
        @InvocableVariable(
            label='Quote ID'
            description='Follow-up 메일을 작성할 대상 Quote 의 18-char Id. 필수.'
            required=true
        )
        public Id quoteId;

        @InvocableVariable(
            label='추가 컨텍스트'
            description='AE 가 메일에 반영할 추가 메시지(예: 단가 5% 인하 검토 가능). 빈값 허용.'
            required=false
        )
        public String additionalContext;
    }

    public class Response {
        @InvocableVariable(label='메일 제목')
        public String emailSubject;

        @InvocableVariable(label='메일 본문')
        public String emailBody;

        @InvocableVariable(label='AI 출처(ai/fallback)')
        public String aiSource;

        @InvocableVariable(label='긴급도(urgent/standard)')
        public String urgency;

        @InvocableVariable(label='발송일로부터 경과 일수')
        public Integer daysSinceSent;

        @InvocableVariable(label='실패 메시지')
        public String aiError;
    }

    @InvocableMethod(
        label='Draft Followup Email'
        description='Quote 의 follow-up 메일 한국어 초안(제목+본문)을 작성합니다. Prompt Builder FollowupDraft 호출, 실패 시 자동 fallback. AE 가 검토 후 발송.'
        category='Sales Cockpit'
    )
    public static List<Response> run(List<Request> reqs) {
        Request req = (reqs != null && !reqs.isEmpty()) ? reqs[0] : new Request();
        Response r = new Response();
        if (req.quoteId == null) {
            r.aiSource = 'fallback';
            r.aiError = 'quoteId is required';
            r.emailSubject = '[견적 회신 부탁] 견적 응답 확인';
            r.emailBody = '안녕하세요. 견적 검토 결과 회신 부탁드립니다. 감사합니다.';
            r.urgency = 'standard';
            r.daysSinceSent = 0;
            return new List<Response>{ r };
        }

        Quote q = loadQuote(req.quoteId);
        r.daysSinceSent = daysSince(q.Sent_Date__c);
        r.urgency       = (r.daysSinceSent >= 7) ? 'urgent' : 'standard';

        try {
            String aiJson = invokePrompt(req.quoteId, req.additionalContext);
            AiResponse ai = parseAi(aiJson);
            r.emailSubject = ai.subject;
            r.emailBody    = ai.body;
            r.aiSource     = 'ai';
        } catch (Exception e) {
            r.emailSubject = buildFallbackSubject(q, r.urgency);
            r.emailBody    = buildFallbackBody(q, req.additionalContext, r.urgency);
            r.aiSource     = 'fallback';
            r.aiError      = e.getMessage();
        }
        return new List<Response>{ r };
    }

    @TestVisible
    private static Integer daysSince(DateTime sentDate) {
        if (sentDate == null) return 0;
        Long deltaMs = DateTime.now().getTime() - sentDate.getTime();
        if (deltaMs <= 0) return 0;
        return (Integer) (deltaMs / (1000L * 60L * 60L * 24L));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Prompt Builder 호출 (OppInsightService 패턴 + D26 stripCodeFences)
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static String invokePrompt(Id quoteId, String additionalContext) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new FollowupException(mockExceptionMessage);
            return mockAiResponse != null
                ? mockAiResponse
                : '{"subject":"[테스트] 견적 검토 부탁","body":"테스트 follow-up 본문"}';
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wvQuote = new ConnectApi.WrappedValue();
        wvQuote.value = new Map<String, Object>{ 'Id' => quoteId };

        Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>{
            'Input:QuoteRecord' => wvQuote
        };

        if (String.isNotBlank(additionalContext)) {
            ConnectApi.WrappedValue wvCtx = new ConnectApi.WrappedValue();
            wvCtx.value = additionalContext;
            params.put('Input:AdditionalContext', wvCtx);
        }
        input.inputParams = params;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);

        if (resp == null) throw new FollowupException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new FollowupException('LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new FollowupException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    @TestVisible
    private static String stripCodeFences(String body) {
        if (String.isBlank(body)) return body;
        String trimmed = body.trim();
        if (!trimmed.startsWith('`')) return trimmed;
        Pattern p = Pattern.compile('(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$');
        Matcher m = p.matcher(trimmed);
        return m.matches() ? m.group(1) : trimmed;
    }

    @TestVisible
    private static AiResponse parseAi(String jsonBody) {
        if (String.isBlank(jsonBody)) throw new FollowupException('Empty AI body');
        String cleaned = stripCodeFences(jsonBody);
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
        AiResponse a = new AiResponse();
        a.subject = String.valueOf(raw.get('subject'));
        a.body    = String.valueOf(raw.get('body'));
        if (String.isBlank(a.subject) || String.isBlank(a.body)) {
            throw new FollowupException('AI response missing subject or body');
        }
        return a;
    }

    private static Quote loadQuote(Id quoteId) {
        List<Quote> qs = [
            SELECT Id, Name, QuoteNumber, Status, Sent_Date__c, GrandTotal,
                   Opportunity.Name, Opportunity.Account.Name, ContactId, Contact.Name
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];
        if (qs.isEmpty()) throw new FollowupException('Quote not found: ' + quoteId);
        return qs[0];
    }

    @TestVisible
    private static String buildFallbackSubject(Quote q, String urgency) {
        String acct = (q.Opportunity != null && q.Opportunity.Account != null)
                        ? q.Opportunity.Account.Name : '';
        String prefix = 'urgent'.equals(urgency) ? '[재요청] ' : '[';
        String suffix = 'urgent'.equals(urgency) ? '' : ']';
        return prefix + (String.isBlank(acct) ? '한도정밀' : acct) + suffix + ' 견적 ' + q.QuoteNumber + ' 회신 부탁드립니다';
    }

    @TestVisible
    private static String buildFallbackBody(Quote q, String additionalContext, String urgency) {
        String hello = (q.Contact != null && String.isNotBlank(q.Contact.Name))
                        ? q.Contact.Name + ' 담당자님,'
                        : '담당자님,';
        String urgencyLine = 'urgent'.equals(urgency)
            ? '발송 후 1주일이 경과하여 다시 한 번 안내 드립니다.\n'
            : '';
        String body = hello + '\n\n'
            + '안녕하세요. 한도정밀 영업 담당입니다.\n'
            + urgencyLine
            + '지난번 발송드린 견적 ' + q.QuoteNumber + ' 검토 결과 회신 부탁드립니다.\n';
        if (String.isNotBlank(additionalContext)) {
            body += '\n참고로 ' + additionalContext + '\n';
        }
        body += '\n추가 요청이나 조정 사항 있으시면 편하게 말씀 주세요. 감사합니다.\n\n한도정밀 영업팀';
        return body;
    }

    private class AiResponse {
        public String subject;
        public String body;
    }

    public class FollowupException extends Exception {}
}
