@IsTest
private class OppInsightService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Insight Test Co.',
            Business_Number__c = '100-00-00009',
            External_Credit_Score__c = 720,
            Long_Term_Debtor__c = false
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Insight Opp',
            AccountId = acc.Id,
            StageName = '발굴',
            CloseDate = Date.today().addDays(30),
            Amount = 1500000
        );
        insert opp;
    }

    @IsTest
    static void testAnalyze_withMockAi() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        OppInsightService.mockAiResponse =
            '{"summary":"베어링 거래 발굴 단계","nextActions":["견적 작성","follow-up 등록"]}';

        Test.startTest();
        OppInsightService.Insight i = OppInsightService.analyze(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, i.score, '점수 반환');
        System.assertEquals('ai', i.aiSource);
        System.assertEquals('베어링 거래 발굴 단계', i.summary);
        System.assertEquals(2, i.nextActions.size());
    }

    @IsTest
    static void testAnalyze_aiFailure_fallback() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        OppInsightService.mockExceptionMessage = 'LLM unavailable';

        Test.startTest();
        OppInsightService.Insight i = OppInsightService.analyze(opp.Id);
        Test.stopTest();

        System.assertEquals('fallback', i.aiSource, 'fallback 모드');
        System.assertNotEquals(null, i.summary);
        System.assert(!i.nextActions.isEmpty());
    }

    @IsTest
    static void testAnalyze_NullThrows() {
        try {
            OppInsightService.analyze(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testScoreCalculation_lowStageNoActivityFlagsRisks() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        OppScoreService.Score s = OppScoreService.calculate(opp.Id);
        Test.stopTest();

        System.assertEquals(10, s.stageScore, '발굴 단계 = 10');
        System.assertEquals(0, s.activityScore, '활동 0건');
        System.assertEquals(15, s.accountScore, '신용점수 720 = 15');
        System.assertEquals(0, s.engagementScore, '견적 0건');
        System.assertEquals(25, s.total, '10+0+15+0=25');
        System.assert(s.riskFactors.contains('최근 14일 활동 0건 (응답 지연 우려)'));
        System.assert(s.riskFactors.contains('연결된 견적 없음 — 견적 작성 필요'));
    }

    @IsTest
    static void testScoreCalculation_longTermDebtor() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        acc.Long_Term_Debtor__c = true;
        update acc;
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        OppScoreService.Score s = OppScoreService.calculate(opp.Id);
        Test.stopTest();

        System.assert(s.riskFactors.contains('Account 장기미수 보유'));
        System.assertEquals(10, s.accountScore, '15 - 5 (장기미수 감점)');
    }
}
