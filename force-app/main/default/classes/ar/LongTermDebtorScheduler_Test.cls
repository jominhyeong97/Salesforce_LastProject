@IsTest
private class LongTermDebtorScheduler_Test {

    @TestSetup
    static void setup() {
        Id stdPb = Test.getStandardPricebookId();

        // A: 장기 미수금 보유 Account (180일+ 미입금)
        Account accOld = new Account(Name='OldDebt Co.', Business_Number__c='100-00-00009', Long_Term_Debtor__c=false);
        // B: 최근 미수금 (180일 미만)
        Account accNew = new Account(Name='NewDebt Co.', Business_Number__c='100-00-00009', Long_Term_Debtor__c=false);
        // C: 이미 Long_Term=true 이지만 실제로는 다 입금됨 (false 로 정정 대상)
        Account accResolved = new Account(Name='Resolved Co.', Business_Number__c='100-00-00009', Long_Term_Debtor__c=true);
        insert new List<Account>{accOld, accNew, accResolved};

        Product2 p = new Product2(Name='P', ProductCode='P-1', IsActive=true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=stdPb, Product2Id=p.Id, UnitPrice=1000, IsActive=true);
        insert pbe;

        // accOld: 200일 전 Order, 입금 없음 → outstanding > 0
        Order o1 = new Order(AccountId=accOld.Id, EffectiveDate=Date.today().addDays(-200),
                             Status='Draft', Pricebook2Id=stdPb, PoNumber='PO-OLD');
        // accNew: 30일 전 Order
        Order o2 = new Order(AccountId=accNew.Id, EffectiveDate=Date.today().addDays(-30),
                             Status='Draft', Pricebook2Id=stdPb, PoNumber='PO-NEW');
        // accResolved: 200일 전 Order 이지만 라인 없음 → TotalAmount=0 → Outstanding=0
        Order o3 = new Order(AccountId=accResolved.Id, EffectiveDate=Date.today().addDays(-200),
                             Status='Draft', Pricebook2Id=stdPb, PoNumber='PO-RES');
        insert new List<Order>{o1, o2, o3};

        // accOld, accNew 에는 라인 추가 (Outstanding > 0)
        insert new List<OrderItem>{
            new OrderItem(OrderId=o1.Id, PricebookEntryId=pbe.Id, Quantity=10, UnitPrice=1000),
            new OrderItem(OrderId=o2.Id, PricebookEntryId=pbe.Id, Quantity=10, UnitPrice=1000)
        };
    }

    @IsTest
    static void testProcess_flagsLongTermAccount() {
        Test.startTest();
        Integer changed = LongTermDebtorScheduler.process();
        Test.stopTest();

        Account a = [SELECT Long_Term_Debtor__c FROM Account WHERE Name='OldDebt Co.' LIMIT 1];
        System.assertEquals(true, a.Long_Term_Debtor__c, '200일 + outstanding>0 → 장기미수 true');
        System.assert(changed >= 1, '최소 1건 갱신');
    }

    @IsTest
    static void testProcess_keepsNewDebtorFalse() {
        Test.startTest();
        LongTermDebtorScheduler.process();
        Test.stopTest();

        Account a = [SELECT Long_Term_Debtor__c FROM Account WHERE Name='NewDebt Co.' LIMIT 1];
        System.assertEquals(false, a.Long_Term_Debtor__c, '30일은 장기 아님');
    }

    @IsTest
    static void testProcess_resolvesPreviouslyFlagged() {
        Test.startTest();
        LongTermDebtorScheduler.process();
        Test.stopTest();

        // Resolved Co. 는 outstanding 0 → 다시 false 로 변경되어야
        Account a = [SELECT Long_Term_Debtor__c FROM Account WHERE Name='Resolved Co.' LIMIT 1];
        System.assertEquals(false, a.Long_Term_Debtor__c,
            'Outstanding=0 이면 기존 true 도 false 로 정정');
    }

    @IsTest
    static void testSchedule_runs() {
        // 실 환경에 'LongTermDebtorDaily' 가 이미 등록돼 있을 수 있어 test 전용 이름으로 직접 schedule.
        Test.startTest();
        String jobId = System.schedule(
            'LongTermDebtorDaily_TEST_' + Datetime.now().getTime(),
            '0 0 2 * * ?',
            new LongTermDebtorScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Schedule job ID 반환');
        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId LIMIT 1];
        System.assertEquals('0 0 2 * * ?', ct.CronExpression);
    }
}
