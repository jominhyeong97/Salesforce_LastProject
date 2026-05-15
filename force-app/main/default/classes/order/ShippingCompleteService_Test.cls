@IsTest
private class ShippingCompleteService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name='Ship Test Co.', Business_Number__c='100-00-00009');
        insert acc;

        Id stdPb = Test.getStandardPricebookId();
        List<Order> orders = new List<Order>{
            new Order(AccountId=acc.Id, EffectiveDate=Date.today().addDays(-7),
                      Status='Draft', Pricebook2Id=stdPb,
                      PoNumber='PO-S-DONE', Production_Status__c='Done'),
            new Order(AccountId=acc.Id, EffectiveDate=Date.today().addDays(-7),
                      Status='Draft', Pricebook2Id=stdPb,
                      PoNumber='PO-S-INPROG', Production_Status__c='InProgress'),
            new Order(AccountId=acc.Id, EffectiveDate=Date.today().addDays(-30),
                      Status='Draft', Pricebook2Id=stdPb,
                      PoNumber='PO-S-SHIPPED', Production_Status__c='Shipped',
                      Shipped_Date__c=Date.today().addDays(-5))
        };
        insert orders;
    }

    @IsTest
    static void testMarkShipped_doneOrder_success() {
        Order o = [SELECT Id FROM Order WHERE PoNumber='PO-S-DONE' LIMIT 1];

        Test.startTest();
        ShippingCompleteService.ShipResult r = ShippingCompleteService.markShipped(
            o.Id, Date.today(), '항공편 출고');
        Test.stopTest();

        System.assertEquals('Shipped', r.productionStatus);
        System.assertEquals(Date.today(), r.shippedDate);
        System.assert(r.message.contains('항공편'), '메시지에 note 포함');

        Order reload = [SELECT Production_Status__c, Shipped_Date__c FROM Order WHERE Id = :o.Id];
        System.assertEquals('Shipped', reload.Production_Status__c);
        System.assertEquals(Date.today(), reload.Shipped_Date__c);
    }

    @IsTest
    static void testMarkShipped_defaultDate_today() {
        Order o = [SELECT Id FROM Order WHERE PoNumber='PO-S-DONE' LIMIT 1];

        Test.startTest();
        ShippingCompleteService.ShipResult r = ShippingCompleteService.markShipped(o.Id, null, null);
        Test.stopTest();

        System.assertEquals(Date.today(), r.shippedDate, '날짜 미입력 → 오늘');
    }

    @IsTest
    static void testMarkShipped_inProgress_blocked() {
        Order o = [SELECT Id FROM Order WHERE PoNumber='PO-S-INPROG' LIMIT 1];

        Test.startTest();
        Boolean failed = false;
        try {
            ShippingCompleteService.markShipped(o.Id, Date.today(), null);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assert(failed, 'InProgress 는 출고 불가');
    }

    @IsTest
    static void testMarkShipped_alreadyShipped_blocked() {
        Order o = [SELECT Id FROM Order WHERE PoNumber='PO-S-SHIPPED' LIMIT 1];

        Test.startTest();
        Boolean failed = false;
        try {
            ShippingCompleteService.markShipped(o.Id, Date.today(), null);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assert(failed, '이미 Shipped 는 재출고 불가');
    }

    @IsTest
    static void testMarkShipped_futureDate_blocked() {
        Order o = [SELECT Id FROM Order WHERE PoNumber='PO-S-DONE' LIMIT 1];

        Test.startTest();
        Boolean failed = false;
        try {
            ShippingCompleteService.markShipped(o.Id, Date.today().addDays(1), null);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();

        System.assert(failed, '미래 출고일은 불가');
    }

    @IsTest
    static void testMarkShipped_nullId_throws() {
        Test.startTest();
        Boolean failed = false;
        try {
            ShippingCompleteService.markShipped(null, null, null);
        } catch (AuraHandledException e) {
            failed = true;
        }
        Test.stopTest();
        System.assert(failed, 'null orderId 예외');
    }
}
