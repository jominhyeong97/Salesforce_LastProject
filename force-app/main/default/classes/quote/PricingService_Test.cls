@IsTest
private class PricingService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Hando Test Co.', Business_Number__c = '100-00-00009');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = '발굴',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Product2 p1 = new Product2(Name = 'Bearing 6201', ProductCode = 'BR-6201', IsActive = true);
        Product2 p2 = new Product2(Name = '단조품 SS-100', ProductCode = 'FG-SS100', IsActive = true);
        insert new List<Product2>{ p1, p2 };

        Id stdPbId = Test.getStandardPricebookId();
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = p1.Id, UnitPrice = 10000, IsActive = true),
            new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = p2.Id, UnitPrice = 50000, IsActive = true)
        };

        Quote q = new Quote(
            Name = 'Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPbId,
            Status = '초안',
            ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        List<PricebookEntry> pbes = [SELECT Id, Product2Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = :stdPbId];
        Map<Id, PricebookEntry> byProduct = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : pbes) byProduct.put(pbe.Product2Id, pbe);

        insert new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = q.Id, PricebookEntryId = byProduct.get(p1.Id).Id,
                Product2Id = p1.Id, Quantity = 100, UnitPrice = 10000, Discount_Amount__c = 0
            ),
            new QuoteLineItem(
                QuoteId = q.Id, PricebookEntryId = byProduct.get(p2.Id).Id,
                Product2Id = p2.Id, Quantity = 10, UnitPrice = 50000, Discount_Amount__c = 20000
            )
        };
    }

    private static Quote findQuote() {
        return [SELECT Id, AE_Edit_Count__c FROM Quote LIMIT 1];
    }

    @IsTest
    static void testGetQuoteSummary() {
        Quote q = findQuote();
        Test.startTest();
        PricingService.QuoteSummaryDTO dto = PricingService.getQuoteSummary(q.Id);
        Test.stopTest();

        System.assertEquals(2, dto.lines.size(), '라인 2건');
        System.assertEquals(1500000, dto.summary.subtotal,    'subtotal = 100*10000 + 10*50000');
        System.assertEquals(20000,   dto.summary.totalDiscount, 'totalDiscount = 0 + 20000');
        System.assertEquals(1480000, dto.summary.netTotal,    'netTotal = subtotal - discount');
        System.assertEquals(2,       dto.summary.lineCount);
        System.assertNotEquals(null, dto.header.name);
    }

    @IsTest
    static void testUpdateLineIncrementsEditCount() {
        Quote q = findQuote();
        QuoteLineItem qli = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1];

        Test.startTest();
        PricingService.QuoteSummaryDTO dto = PricingService.updateLine(qli.Id, 200, 12000, 50000);
        Test.stopTest();

        QuoteLineItem updated = [SELECT Quantity, UnitPrice, Discount_Amount__c FROM QuoteLineItem WHERE Id = :qli.Id];
        System.assertEquals(200,   updated.Quantity);
        System.assertEquals(12000, updated.UnitPrice);
        System.assertEquals(50000, updated.Discount_Amount__c);

        Quote refreshed = [SELECT AE_Edit_Count__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(1, refreshed.AE_Edit_Count__c, '편집 카운트 1 증가');

        System.assertNotEquals(null, dto.summary, '요약 반환');
    }

    @IsTest
    static void testAddLine() {
        Quote q = findQuote();
        Product2 newP = new Product2(Name = 'Mixer M-200', ProductCode = 'MX-200', IsActive = true);
        insert newP;
        Id stdPbId = Test.getStandardPricebookId();
        insert new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = newP.Id, UnitPrice = 80000, IsActive = true);

        Test.startTest();
        PricingService.QuoteSummaryDTO dto = PricingService.addLine(q.Id, newP.Id, 5);
        Test.stopTest();

        System.assertEquals(3, dto.lines.size(), '라인 3건');
        System.assertEquals(1900000, dto.summary.subtotal, 'subtotal = 1500000 + 5*80000');

        Quote refreshed = [SELECT AE_Edit_Count__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(1, refreshed.AE_Edit_Count__c);
    }

    @IsTest
    static void testDeleteLine() {
        Quote q = findQuote();
        QuoteLineItem qli = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1];

        Test.startTest();
        PricingService.QuoteSummaryDTO dto = PricingService.deleteLine(qli.Id);
        Test.stopTest();

        System.assertEquals(1, dto.lines.size(), '라인 1건 남음');
        Quote refreshed = [SELECT AE_Edit_Count__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals(1, refreshed.AE_Edit_Count__c);
    }

    @IsTest
    static void testGetQuoteSummaryNullThrows() {
        try {
            PricingService.getQuoteSummary(null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testGetActiveProducts() {
        Quote q = findQuote();
        Test.startTest();
        List<PricingService.ProductOptionDTO> opts = PricingService.getActiveProducts(q.Id);
        Test.stopTest();
        System.assert(opts.size() >= 2, '최소 2개 Product 노출');
    }

    @IsTest
    static void testAddLineNoProductInPricebook() {
        Quote q = findQuote();
        Product2 orphan = new Product2(Name = 'Orphan Product', ProductCode = 'OR-999', IsActive = true);
        insert orphan;

        Test.startTest();
        try {
            PricingService.addLine(q.Id, orphan.Id, 3);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}
