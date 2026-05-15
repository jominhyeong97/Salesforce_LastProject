/**
 * OppInsightService — 하이브리드 Opportunity 인사이트.
 *   - 정량 점수: OppScoreService (Apex)
 *   - 자연어 요약·다음 액션: Prompt Builder OpportunityInsight Template
 *   - LLM 실패 시 Apex fallback 요약 제공 (graceful degrade)
 *
 * @group Opp
 */
public with sharing class OppInsightService {

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'OpportunityInsight';
    @TestVisible private static final String CAPABILITY        = '';
    @TestVisible private static final String APPLICATION_NAME  = 'PromptBuilderPreview';

    @TestVisible private static String mockAiResponse;
    @TestVisible private static String mockExceptionMessage;

    @AuraEnabled(cacheable=true)
    public static Insight analyze(Id opportunityId) {
        if (opportunityId == null) throw newAura('opportunityId is required');

        OppScoreService.Score s = OppScoreService.calculate(opportunityId);
        Opportunity opp = [
            SELECT Id, Name, StageName, Amount, Account.Name, Account.External_Credit_Score__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];

        Insight out = new Insight();
        out.score            = s.total;
        out.stageScore       = s.stageScore;
        out.activityScore    = s.activityScore;
        out.accountScore     = s.accountScore;
        out.engagementScore  = s.engagementScore;
        out.risks            = s.riskFactors;

        try {
            String aiJson = invokePromptForOpp(opportunityId);
            AiResponse ai = parseAi(aiJson);
            out.summary     = ai.summary;
            out.nextActions = ai.nextActions;
            out.aiSource    = 'ai';
        } catch (Exception e) {
            out.summary     = buildFallbackSummary(opp, s);
            out.nextActions = buildFallbackActions(s);
            out.aiSource    = 'fallback';
            out.aiError     = e.getMessage();
        }
        return out;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Prompt Builder 호출 (Day 5 OCR 패턴)
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static String invokePromptForOpp(Id opportunityId) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new InsightException(mockExceptionMessage);
            return mockAiResponse != null
                ? mockAiResponse
                : '{"summary":"테스트 거래 요약","nextActions":["테스트 액션 1","테스트 액션 2"]}';
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = new Map<String, Object>{ 'Id' => opportunityId };
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:OppRecord' => wv
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);

        if (resp == null) throw new InsightException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new InsightException('LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new InsightException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    private static AiResponse parseAi(String jsonBody) {
        if (String.isBlank(jsonBody)) throw new InsightException('Empty AI body');
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        AiResponse a = new AiResponse();
        a.summary = String.valueOf(raw.get('summary'));
        a.nextActions = new List<String>();
        Object actions = raw.get('nextActions');
        if (actions instanceof List<Object>) {
            for (Object o : (List<Object>) actions) {
                a.nextActions.add(String.valueOf(o));
            }
        }
        return a;
    }

    private static String buildContext(Opportunity opp, OppScoreService.Score s) {
        return  '거래 점수: ' + s.total + '/100 (단계 ' + s.stageScore +
                ' + 활동 ' + s.activityScore + ' + Account ' + s.accountScore +
                ' + Engagement ' + s.engagementScore + ')\n' +
                '거래 단계: ' + opp.StageName + '\n' +
                '고객사: ' + (opp.Account != null ? opp.Account.Name : '미상') + '\n' +
                '예상 금액: ' + (opp.Amount != null ? opp.Amount.format() : '미상') + '\n' +
                '위험 요소: ' + (s.riskFactors.isEmpty() ? '없음' : String.join(s.riskFactors, ' / '));
    }

    private static String buildFallbackSummary(Opportunity opp, OppScoreService.Score s) {
        return (opp.Account != null && opp.Account.Name != null ? opp.Account.Name : '고객사') +
               ' 거래 — ' + opp.StageName + ' 단계, 종합 점수 ' + s.total + '점.';
    }

    private static List<String> buildFallbackActions(OppScoreService.Score s) {
        List<String> out = new List<String>();
        if (s.stageScore <= 10)       out.add('견적 작성 단계로 빠른 전환');
        if (s.activityScore == 0)     out.add('AE follow-up Task 등록 (최근 활동 없음)');
        if (s.engagementScore < 10)   out.add('견적 발송 또는 응답 추적 활성화');
        if (out.isEmpty())            out.add('거래 진행 정상 — 단계 게이트 모니터링');
        return out;
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs
    // ─────────────────────────────────────────────────────────────────────

    public class Insight {
        @AuraEnabled public Integer score;
        @AuraEnabled public Integer stageScore;
        @AuraEnabled public Integer activityScore;
        @AuraEnabled public Integer accountScore;
        @AuraEnabled public Integer engagementScore;
        @AuraEnabled public List<String> risks;
        @AuraEnabled public String summary;
        @AuraEnabled public List<String> nextActions;
        @AuraEnabled public String aiSource;     // 'ai' | 'fallback'
        @AuraEnabled public String aiError;
    }

    private class AiResponse {
        public String summary;
        public List<String> nextActions;
    }

    public class InsightException extends Exception {}
}
