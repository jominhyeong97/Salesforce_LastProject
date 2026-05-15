@IsTest
private class PaymentCheckAction_Test {

    @TestSetup
    static void setup() {
        Account a1 = new Account(Name='페이체크고객A', Business_Number__c='100-00-00009');
        Account a2 = new Account(Name='페이체크고객B', Business_Number__c='100-00-00009');
        Account a3 = new Account(Name='페이체크고객C', Business_Number__c='100-00-00009');
        insert new List<Account>{ a1, a2, a3 };

        Pricebook2 pb = new Pricebook2(Id=Test.getStandardPricebookId());
        update pb;

        Product2 prod = new Product2(Name='페이체크부품', IsActive=true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id=pb.Id, Product2Id=prod.Id,
            UnitPrice=1000000, IsActive=true
        );
        insert pbe;

        Contract c1 = new Contract(AccountId=a1.Id, Status='Draft', StartDate=Date.today().addDays(-30), ContractTerm=12);
        Contract c2 = new Contract(AccountId=a2.Id, Status='Draft', StartDate=Date.today().addDays(-30), ContractTerm=12);
        Contract c3 = new Contract(AccountId=a3.Id, Status='Draft', StartDate=Date.today().addDays(-30), ContractTerm=12);
        insert new List<Contract>{ c1, c2, c3 };

        Order o1 = new Order(
            AccountId=a1.Id, ContractId=c1.Id, EffectiveDate=Date.today().addDays(-10),
            Status='Draft', Pricebook2Id=pb.Id
        );
        Order o2 = new Order(
            AccountId=a2.Id, ContractId=c2.Id, EffectiveDate=Date.today().addDays(-10),
            Status='Draft', Pricebook2Id=pb.Id
        );
        Order o3 = new Order(
            AccountId=a3.Id, ContractId=c3.Id, EffectiveDate=Date.today().addDays(-10),
            Status='Draft', Pricebook2Id=pb.Id
        );
        insert new List<Order>{ o1, o2, o3 };

        insert new List<OrderItem>{
            new OrderItem(OrderId=o1.Id, PricebookEntryId=pbe.Id, Quantity=10, UnitPrice=1000000),
            new OrderItem(OrderId=o2.Id, PricebookEntryId=pbe.Id, Quantity=5,  UnitPrice=1000000),
            new OrderItem(OrderId=o3.Id, PricebookEntryId=pbe.Id, Quantity=8,  UnitPrice=1000000)
        };

        // 오늘 입금: a1=5M, a2=2M / 어제 입금: a3=3M
        insert new List<Payment__c>{
            new Payment__c(Order__c=o1.Id, Status__c='Paid', Paid_Date__c=Date.today(),
                           Paid_Amount__c=5000000, Memo__c='오늘1'),
            new Payment__c(Order__c=o2.Id, Status__c='Paid', Paid_Date__c=Date.today(),
                           Paid_Amount__c=2000000, Memo__c='오늘2'),
            new Payment__c(Order__c=o3.Id, Status__c='Paid', Paid_Date__c=Date.today().addDays(-1),
                           Paid_Amount__c=3000000, Memo__c='어제')
        };

        // Account.Total_AR__c 채우기 (Apex 갱신, formula 아님)
        Decimal o1AR = [SELECT Outstanding_Amount__c FROM Order WHERE Id=:o1.Id].Outstanding_Amount__c;
        Decimal o2AR = [SELECT Outstanding_Amount__c FROM Order WHERE Id=:o2.Id].Outstanding_Amount__c;
        Decimal o3AR = [SELECT Outstanding_Amount__c FROM Order WHERE Id=:o3.Id].Outstanding_Amount__c;
        update new List<Account>{
            new Account(Id=a1.Id, Total_AR__c=o1AR == null ? 5000000 : o1AR),
            new Account(Id=a2.Id, Total_AR__c=o2AR == null ? 3000000 : o2AR),
            new Account(Id=a3.Id, Total_AR__c=o3AR == null ? 5000000 : o3AR)
        };
    }

    @IsTest
    static void testToday_returnsTodayPaymentsAggregated() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'today';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        System.assertEquals(1, outs.size());
        PaymentCheckAction.Response r = outs[0];
        System.assertEquals('today', r.mode);
        System.assertEquals(true, r.found, 'today payments expected');
        System.assertEquals(2, r.count, '오늘 입금 2건');
        System.assertEquals(7000000, r.totalAmount, '합계 7M');
        System.assert(r.summary.contains('오늘 입금 2건'), 'summary: ' + r.summary);
        System.assert(r.summary.contains('페이체크고객A'),
            '최다 — 페이체크고객A 5M 예상, got: ' + r.summary);
    }

    @IsTest
    static void testWeek_includesLast7Days() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'week';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals('week', r.mode);
        System.assertEquals(3, r.count, '최근 7일 입금 3건');
        System.assertEquals(10000000, r.totalAmount, '합계 10M');
    }

    @IsTest
    static void testAccount_byName_exactMatch() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'account';
        req.accountName = '페이체크고객A';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals('account', r.mode);
        System.assertEquals(true, r.found);
        System.assertNotEquals(null, r.accountId);
        System.assertEquals('페이체크고객A', r.accountName);
        System.assert(r.summary.contains('페이체크고객A'), 'summary: ' + r.summary);
    }

    @IsTest
    static void testAccount_byName_likeFallback() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'account';
        req.accountName = '페이체크고객'; // exact match 없음 → LIKE 매칭
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals(true, r.found);
        System.assert(r.accountName.startsWith('페이체크고객'));
    }

    @IsTest
    static void testAccount_byId() {
        Account a = [SELECT Id FROM Account WHERE Name='페이체크고객A' LIMIT 1];
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'account';
        req.accountId = a.Id;
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals(a.Id, r.accountId);
        System.assertEquals('페이체크고객A', r.accountName);
    }

    @IsTest
    static void testAccount_notFound_returnsErrorSummary() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'account';
        req.accountName = '존재하지않는회사ZZZZZ';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals(false, r.found);
        System.assert(r.summary.contains('찾지 못'), 'summary: ' + r.summary);
    }

    @IsTest
    static void testAtRisk_returnsTopAccounts() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'atrisk';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals('atrisk', r.mode);
        System.assertEquals(true, r.found);
        System.assert(r.count > 0, 'AR 보유 Account 있음');
        System.assert(r.summary.contains('미수금 상위'), 'summary: ' + r.summary);
    }

    @IsTest
    static void testDefaultMode_blankRequest_treatedAsToday() {
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ new PaymentCheckAction.Request() });
        System.assertEquals('today', outs[0].mode);
    }

    @IsTest
    static void testUnknownMode_fallsBackToToday() {
        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'galaxybrain';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });
        System.assertEquals('today', outs[0].mode);
    }

    @IsTest
    static void testToday_noPaymentsToday_returnsEmptySummary() {
        // wipe today's payments
        delete [SELECT Id FROM Payment__c WHERE Paid_Date__c = TODAY];

        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'today';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals(false, r.found);
        System.assertEquals(0, r.count);
        System.assert(r.summary.contains('내역이 없'), 'summary: ' + r.summary);
    }

    @IsTest
    static void testAtRisk_noArAccounts_returnsCleanSummary() {
        update new List<Account>{
            new Account(Id=[SELECT Id FROM Account WHERE Name='페이체크고객A' LIMIT 1].Id, Total_AR__c=0),
            new Account(Id=[SELECT Id FROM Account WHERE Name='페이체크고객B' LIMIT 1].Id, Total_AR__c=0),
            new Account(Id=[SELECT Id FROM Account WHERE Name='페이체크고객C' LIMIT 1].Id, Total_AR__c=0)
        };
        // setup() 외 다른 시드 Account 도 0 으로 처리
        List<Account> others = [SELECT Id FROM Account WHERE Total_AR__c > 0];
        for (Account a : others) a.Total_AR__c = 0;
        if (!others.isEmpty()) update others;

        PaymentCheckAction.Request req = new PaymentCheckAction.Request();
        req.mode = 'atrisk';
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>{ req });

        PaymentCheckAction.Response r = outs[0];
        System.assertEquals(false, r.found);
        System.assert(r.summary.contains('회수 양호'), 'summary: ' + r.summary);
    }

    @IsTest
    static void testEmptyRequestList_doesNotThrow() {
        List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
            new List<PaymentCheckAction.Request>());
        System.assertEquals(1, outs.size(), 'empty req → defaults to today single Response');
    }
}
