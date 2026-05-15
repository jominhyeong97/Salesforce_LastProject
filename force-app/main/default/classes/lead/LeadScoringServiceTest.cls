@isTest
private class LeadScoringServiceTest {

    @TestSetup
    static void setup() {
        // 사업자번호는 LeadScoringServiceTest 범위 외 — Account 트리거 통과 위해 비워둠
        insert new Account(Name = '한라정공');
    }

    @isTest
    static void testNullSafe() {
        System.assertEquals(0, LeadScoringService.calculateScore(null));
    }

    @isTest
    static void testPhoneOnly() {
        Lead l = new Lead(Company = 'NoMatchCo', LastName = 'Kim', Source_Channel__c = 'PHONE');
        System.assertEquals(30, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testEmailChannel() {
        Lead l = new Lead(Company = 'NoMatchCo', LastName = 'Lee', Source_Channel__c = 'EMAIL');
        System.assertEquals(20, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testVisitChannel() {
        Lead l = new Lead(Company = 'NoMatchCo', LastName = 'Park', Source_Channel__c = 'VISIT');
        System.assertEquals(40, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testPastDealBonus() {
        Lead l = new Lead(Company = '한라정공', LastName = 'Park', Source_Channel__c = 'PHONE');
        System.assertEquals(50, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testFullScore() {
        Lead l = new Lead(
            Company = '한라정공',
            LastName = 'Choi',
            Source_Channel__c = 'VISIT',
            RFQ_Spec_JSON__c = '{"partName":"베어링","quantity":100}'
        );
        System.assertEquals(80, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testSpecWithoutQuantity() {
        Lead l = new Lead(
            Company = 'NoMatchCo',
            LastName = 'Han',
            Source_Channel__c = 'PHONE',
            RFQ_Spec_JSON__c = '{"partName":"베어링"}'
        );
        // PHONE 30 + spec 10 = 40
        System.assertEquals(40, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testInvalidJsonIgnored() {
        Lead l = new Lead(
            Company = 'NoMatchCo',
            LastName = 'Han',
            Source_Channel__c = 'PHONE',
            RFQ_Spec_JSON__c = '{not valid json'
        );
        // 파싱 실패해도 spec 입력 자체로 +10
        System.assertEquals(40, LeadScoringService.calculateScore(l));
    }

    @isTest
    static void testApplyScore() {
        Lead l = new Lead(Company = '한라정공', LastName = 'Park', Source_Channel__c = 'PHONE');
        insert l;

        Test.startTest();
        Lead updated = LeadScoringService.applyScore(l.Id);
        Test.stopTest();

        System.assertEquals(50, updated.Lead_Score__c.intValue());
    }

    @isTest
    static void testApplyScoreNullId() {
        System.assertEquals(null, LeadScoringService.applyScore(null));
    }
}
