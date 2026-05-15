@IsTest
private class GetCrossSellCandidatesAction_Test {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = '교차판매테스트', Business_Number__c = '100-00-00009');
        insert a;

        Id stdPb = Test.getStandardPricebookId();

        // 3 Products 같은 Family
        Product2 p1 = new Product2(Name = '베어링 6204', ProductCode = 'BR-6204', Family = '베어링', IsActive = true);
        Product2 p2 = new Product2(Name = '베어링 6304', ProductCode = 'BR-6304', Family = '베어링', IsActive = true);
        Product2 p3 = new Product2(Name = '베어링 6404', ProductCode = 'BR-6404', Family = '베어링', IsActive = true);
        // 다른 Family 1 (대조군)
        Product2 p4 = new Product2(Name = '단조품 SKD11', ProductCode = 'FG-SKD11', Family = '단조품', IsActive = true);
        insert new List<Product2>{ p1, p2, p3, p4 };

        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 p : new List<Product2>{p1,p2,p3,p4}) {
            pbes.add(new PricebookEntry(Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 1000, IsActive = true));
        }
        insert pbes;

        // 고객이 p1 발주 (베어링 Family)
        Order o = new Order(
            AccountId = a.Id, EffectiveDate = Date.today(), Status = 'Draft',
            Pricebook2Id = stdPb, PoNumber = 'PO-CS-001'
        );
        insert o;
        insert new OrderItem(
            OrderId = o.Id, PricebookEntryId = pbes[0].Id, Product2Id = p1.Id,
            Quantity = 10, UnitPrice = 1000
        );

        // p2, p3 는 다른 고객들이 발주 → 인기도 차이 만들기 (p2 가 더 인기)
        Account other = new Account(Name = '다른 고객');
        insert other;
        Order o2 = new Order(AccountId = other.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = stdPb, PoNumber = 'PO-CS-002');
        insert o2;
        insert new List<OrderItem>{
            new OrderItem(OrderId = o2.Id, PricebookEntryId = pbes[1].Id, Product2Id = p2.Id, Quantity = 1, UnitPrice = 1000),
            new OrderItem(OrderId = o2.Id, PricebookEntryId = pbes[1].Id, Product2Id = p2.Id, Quantity = 1, UnitPrice = 1000),
            new OrderItem(OrderId = o2.Id, PricebookEntryId = pbes[2].Id, Product2Id = p3.Id, Quantity = 1, UnitPrice = 1000)
        };
    }

    @IsTest
    static void testRun_byAccountId_returnsCrossSellCandidates() {
        Account a = [SELECT Id FROM Account WHERE Name = '교차판매테스트' LIMIT 1];
        GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
        req.accountId = a.Id;

        Test.startTest();
        List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
            new List<GetCrossSellCandidatesAction.Request>{ req });
        Test.stopTest();

        GetCrossSellCandidatesAction.Response r = outs[0];
        System.assertEquals(true, r.found);
        System.assertEquals(a.Id, r.accountId);
        // p2(인기 2) + p3(인기 1) — 베어링 Family 에서 p1 제외한 후보 2건
        System.assertEquals(2, r.candidateCount);
        System.assert(r.summary.contains('교차판매테스트'));
        System.assert(r.summary.contains('베어링'));
        System.assertNotEquals('[]', r.candidatesJson);
    }

    @IsTest
    static void testRun_byAccountName_partialMatch() {
        GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
        req.accountName = '교차판매';
        List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
            new List<GetCrossSellCandidatesAction.Request>{ req });
        System.assertEquals(true, outs[0].found);
    }

    @IsTest
    static void testRun_noAccount_notFound() {
        GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
        req.accountName = '존재하지않는회사_XYZ';
        List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
            new List<GetCrossSellCandidatesAction.Request>{ req });
        System.assertEquals(false, outs[0].found);
        System.assertEquals(0, outs[0].candidateCount);
    }

    @IsTest
    static void testRun_accountWithoutOrders_emptyCandidates() {
        Account fresh = new Account(Name = '신규고객');
        insert fresh;
        GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
        req.accountId = fresh.Id;
        List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
            new List<GetCrossSellCandidatesAction.Request>{ req });
        System.assertEquals(true, outs[0].found);
        System.assertEquals(0, outs[0].candidateCount);
        System.assert(outs[0].summary.contains('과거 발주 이력이 없'));
    }

    @IsTest
    static void testRun_maxResults_limitsOutput() {
        Account a = [SELECT Id FROM Account WHERE Name = '교차판매테스트' LIMIT 1];
        GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
        req.accountId = a.Id;
        req.maxResults = 1;
        List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
            new List<GetCrossSellCandidatesAction.Request>{ req });
        System.assertEquals(1, outs[0].candidateCount);
    }

    @IsTest
    static void testRun_emptyRequest_returnsNotFound() {
        List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(null);
        System.assertEquals(false, outs[0].found);

        outs = GetCrossSellCandidatesAction.run(new List<GetCrossSellCandidatesAction.Request>());
        System.assertEquals(false, outs[0].found);
    }
}
