@IsTest
private class OrderTriggerHandler_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name='Test Co.', Business_Number__c='100-00-00009');
        insert acc;

        Id stdPb = Test.getStandardPricebookId();

        Product2 p1 = new Product2(Name='Bearing-001', ProductCode='BR-001', IsActive=true);
        Product2 p2 = new Product2(Name='Forging-002', ProductCode='FG-002', IsActive=true);
        insert new List<Product2>{p1, p2};

        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id=stdPb, Product2Id=p1.Id, UnitPrice=1000, IsActive=true
        );
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id=stdPb, Product2Id=p2.Id, UnitPrice=5000, IsActive=true
        );
        insert new List<PricebookEntry>{pbe1, pbe2};

        Opportunity opp = new Opportunity(
            Name='Test Opp', AccountId=acc.Id,
            StageName='발굴', CloseDate=Date.today().addDays(30),
            Pricebook2Id=stdPb
        );
        insert opp;

        Quote q = new Quote(
            Name='Q-Test-001', OpportunityId=opp.Id,
            Pricebook2Id=stdPb, Status='수락'
        );
        insert q;

        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbe1.Id,
                              Quantity=10, UnitPrice=1000, Discount_Amount__c=0),
            new QuoteLineItem(QuoteId=q.Id, PricebookEntryId=pbe2.Id,
                              Quantity=5,  UnitPrice=5000, Discount_Amount__c=500)
        };
    }

    @IsTest
    static void testCopyLines_basicAndDiscountDistribution() {
        Opportunity opp = [SELECT Id, AccountId, Pricebook2Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Order o = new Order(
            AccountId=opp.AccountId, Opportunity__c=opp.Id,
            EffectiveDate=Date.today(), Status='Draft',
            Pricebook2Id=opp.Pricebook2Id, PoNumber='PO-T-0001'
        );
        insert o;
        Test.stopTest();

        List<OrderItem> items = [
            SELECT Quantity, UnitPrice FROM OrderItem
            WHERE OrderId = :o.Id ORDER BY Quantity DESC
        ];
        System.assertEquals(2, items.size(), '2 라인 복사');
        System.assertEquals(10, items[0].Quantity);
        System.assertEquals(1000, items[0].UnitPrice, '할인 없음 → UnitPrice 그대로');
        System.assertEquals(5, items[1].Quantity);
        System.assertEquals(4900, items[1].UnitPrice,
            '할인 500/5=100 → effective=5000-100=4900 (Quote 총액과 일치)');
    }

    @IsTest
    static void testCopyLines_noOpportunity() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Order o = new Order(
            AccountId=acc.Id, EffectiveDate=Date.today(),
            Status='Draft', Pricebook2Id=Test.getStandardPricebookId(),
            PoNumber='PO-T-0002'
        );
        insert o;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM OrderItem WHERE OrderId = :o.Id],
            'Opp 없으면 라인 복사 안 함');
    }

    @IsTest
    static void testCopyLines_noAcceptedQuote() {
        Account acc = new Account(Name='No Quote Co.', Business_Number__c='100-00-00009');
        insert acc;
        Opportunity opp = new Opportunity(
            Name='No Quote Opp', AccountId=acc.Id,
            StageName='발굴', CloseDate=Date.today().addDays(30),
            Pricebook2Id=Test.getStandardPricebookId()
        );
        insert opp;

        Test.startTest();
        Order o = new Order(
            AccountId=acc.Id, Opportunity__c=opp.Id,
            EffectiveDate=Date.today(), Status='Draft',
            Pricebook2Id=Test.getStandardPricebookId(),
            PoNumber='PO-T-0003'
        );
        insert o;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM OrderItem WHERE OrderId = :o.Id],
            '수락 Quote 없으면 라인 복사 안 함');
    }

    @IsTest
    static void testCopyLines_emptyQuote() {
        Account acc = new Account(Name='Empty Q Co.', Business_Number__c='100-00-00009');
        insert acc;
        Opportunity opp = new Opportunity(
            Name='Empty Q Opp', AccountId=acc.Id,
            StageName='발굴', CloseDate=Date.today().addDays(30),
            Pricebook2Id=Test.getStandardPricebookId()
        );
        insert opp;
        insert new Quote(
            Name='Q-Empty', OpportunityId=opp.Id,
            Pricebook2Id=Test.getStandardPricebookId(), Status='수락'
        );  // 라인 0

        Test.startTest();
        Order o = new Order(
            AccountId=acc.Id, Opportunity__c=opp.Id,
            EffectiveDate=Date.today(), Status='Draft',
            Pricebook2Id=Test.getStandardPricebookId(),
            PoNumber='PO-T-0004'
        );
        insert o;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM OrderItem WHERE OrderId = :o.Id],
            '빈 Quote → 라인 0건, 에러 없음');
    }

    @IsTest
    static void testCopyLines_bulk() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry LIMIT 1];

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 9; i++) {
            opps.add(new Opportunity(
                Name='Bulk Opp ' + i, AccountId=acc.Id,
                StageName='발굴', CloseDate=Date.today().addDays(30),
                Pricebook2Id=stdPb
            ));
        }
        insert opps;

        List<Quote> quotes = new List<Quote>();
        for (Opportunity opp : opps) {
            quotes.add(new Quote(
                Name='Q-B-' + opp.Id, OpportunityId=opp.Id,
                Pricebook2Id=stdPb, Status='수락'
            ));
        }
        insert quotes;

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Quote q : quotes) {
            qlis.add(new QuoteLineItem(
                QuoteId=q.Id, PricebookEntryId=pbe.Id,
                Quantity=10, UnitPrice=1000
            ));
        }
        insert qlis;

        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 9; i++) {
            orders.add(new Order(
                AccountId=acc.Id, Opportunity__c=opps[i].Id,
                EffectiveDate=Date.today(), Status='Draft',
                Pricebook2Id=stdPb, PoNumber='PO-B-' + i
            ));
        }

        Test.startTest();
        insert orders;
        Test.stopTest();

        System.assertEquals(9,
            [SELECT COUNT() FROM OrderItem WHERE OrderId IN :orders],
            '9 Order × 1 라인 = 9 OrderItem (벌크)');
    }

    @IsTest
    static void testHandler_nullInputSafe() {
        Test.startTest();
        OrderTriggerHandler.copyQuoteLinesOnInsert(null);
        OrderTriggerHandler.copyQuoteLinesOnInsert(new List<Order>());
        Test.stopTest();
        System.assert(true, 'null/빈 입력 NPE 없음');
    }
}
