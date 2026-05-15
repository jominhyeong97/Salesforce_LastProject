@IsTest
private class AiQuoteDraftService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'AI Test Co.', Business_Number__c = '100-00-00009');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'AI Draft Opp',
            AccountId = acc.Id,
            StageName = '발굴',
            CloseDate = Date.today().addDays(30),
            Description = '{"partName":"베어링","quantity":50}'
        );
        insert opp;

        Product2 p1 = new Product2(Name = 'SKF 베어링 6201', ProductCode = 'BR-6201', IsActive = true);
        Product2 p2 = new Product2(Name = '단조품 SS-100', ProductCode = 'FG-SS100', IsActive = true);
        insert new List<Product2>{ p1, p2 };

        Id stdPbId = Test.getStandardPricebookId();
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = p1.Id, UnitPrice = 12000, IsActive = true),
            new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = p2.Id, UnitPrice = 80000, IsActive = true)
        };
    }

    @IsTest
    static void testGenerateAiQuote_JsonSpec() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        AiQuoteDraftService.AiDraftResult r = AiQuoteDraftService.generateAiQuote(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, r.quoteId);
        System.assertEquals(0.85, r.confidence, '베어링 키워드 매칭 0.85');
        System.assert(r.matchedProductName.contains('베어링'), '베어링 제품 매칭');

        Quote q = [SELECT Status, AI_Draft_Confidence__c FROM Quote WHERE Id = :r.quoteId];
        System.assertEquals('초안', q.Status);
        System.assertEquals(0.85, q.AI_Draft_Confidence__c);

        QuoteLineItem qli = [SELECT Quantity, UnitPrice FROM QuoteLineItem WHERE QuoteId = :r.quoteId LIMIT 1];
        System.assertEquals(50, qli.Quantity, 'spec.quantity 반영');
        System.assertEquals(12000, qli.UnitPrice);
    }

    @IsTest
    static void testGenerateAiQuote_FreeText() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Description = '단조품이 100개 정도 필요합니다.';
        update opp;

        Test.startTest();
        AiQuoteDraftService.AiDraftResult r = AiQuoteDraftService.generateAiQuote(opp.Id);
        Test.stopTest();

        System.assertEquals(0.85, r.confidence);
        System.assert(r.matchedProductName.contains('단조품'));
    }

    @IsTest
    static void testGenerateAiQuote_EmptyDescription_DefaultMatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Description = null;
        update opp;

        Test.startTest();
        AiQuoteDraftService.AiDraftResult r = AiQuoteDraftService.generateAiQuote(opp.Id);
        Test.stopTest();

        System.assertEquals(0.50, r.confidence, '미상 시 default 0.50');
    }

    @IsTest
    static void testGenerateAiQuote_NullThrows() {
        try {
            AiQuoteDraftService.generateAiQuote(null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
