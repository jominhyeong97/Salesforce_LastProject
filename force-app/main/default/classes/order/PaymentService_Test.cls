@IsTest
private class PaymentService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name='Pay Test Co.', Business_Number__c='100-00-00009');
        insert acc;

        Id stdPb = Test.getStandardPricebookId();
        Product2 p = new Product2(Name='Pay-Part', ProductCode='PP-001', IsActive=true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id=stdPb, Product2Id=p.Id, UnitPrice=1000, IsActive=true
        );
        insert pbe;

        Order o = new Order(
            AccountId=acc.Id, EffectiveDate=Date.today(),
            Status='Draft', Pricebook2Id=stdPb, PoNumber='PO-PAY-001'
        );
        insert o;
        insert new OrderItem(
            OrderId=o.Id, PricebookEntryId=pbe.Id, Quantity=10, UnitPrice=1000
        );
        // TotalAmount = 10,000
    }

    @IsTest
    static void testRegister_single_updatesOrderAndAccount() {
        Order o = [SELECT Id, TotalAmount FROM Order LIMIT 1];

        Test.startTest();
        PaymentService.PaymentResult r = PaymentService.register(o.Id, Date.today(), 3000, '1차 입금');
        Test.stopTest();

        System.assertEquals(3000, r.totalPaid);
        System.assertEquals(7000, r.outstanding);
        System.assertEquals(10000, r.totalAmount);

        Order reload = [SELECT Total_Paid_Amount__c, Outstanding_Amount__c FROM Order WHERE Id = :o.Id];
        System.assertEquals(3000, reload.Total_Paid_Amount__c);
        System.assertEquals(7000, reload.Outstanding_Amount__c);

        Account a = [SELECT Total_AR__c FROM Account LIMIT 1];
        System.assertEquals(7000, a.Total_AR__c, 'Account.Total_AR 자동 갱신');
    }

    @IsTest
    static void testRegister_threeInstallments_sumsCorrectly() {
        Order o = [SELECT Id FROM Order LIMIT 1];

        Test.startTest();
        PaymentService.register(o.Id, Date.today().addDays(-30), 3000, '1차');
        PaymentService.register(o.Id, Date.today().addDays(-15), 3000, '2차');
        PaymentService.register(o.Id, Date.today(),              4000, '3차');
        Test.stopTest();

        Order reload = [SELECT Total_Paid_Amount__c, Outstanding_Amount__c FROM Order WHERE Id = :o.Id];
        System.assertEquals(10000, reload.Total_Paid_Amount__c);
        System.assertEquals(0,     reload.Outstanding_Amount__c, '완납');

        Account a = [SELECT Total_AR__c FROM Account LIMIT 1];
        System.assertEquals(0, a.Total_AR__c, '완납 후 미수금 0');

        System.assertEquals(3, [SELECT COUNT() FROM Payment__c WHERE Order__c = :o.Id]);
    }

    @IsTest
    static void testRegister_defaultDate_today() {
        Order o = [SELECT Id FROM Order LIMIT 1];
        Test.startTest();
        PaymentService.PaymentResult r = PaymentService.register(o.Id, null, 1000, null);
        Test.stopTest();

        Payment__c p = [SELECT Paid_Date__c FROM Payment__c WHERE Id = :r.paymentId];
        System.assertEquals(Date.today(), p.Paid_Date__c, '날짜 미입력 → 오늘');
    }

    @IsTest
    static void testRegister_zeroAmount_throws() {
        Order o = [SELECT Id FROM Order LIMIT 1];
        assertThrows('amount=0', new ZeroCall(o.Id));
    }

    @IsTest
    static void testRegister_negativeAmount_throws() {
        Order o = [SELECT Id FROM Order LIMIT 1];
        assertThrows('amount=-100', new NegCall(o.Id));
    }

    @IsTest
    static void testRegister_futureDate_throws() {
        Order o = [SELECT Id FROM Order LIMIT 1];
        assertThrows('future date', new FutureCall(o.Id));
    }

    @IsTest
    static void testRegister_nullOrderId_throws() {
        assertThrows('null orderId', new NullCall());
    }

    @IsTest
    static void testGetSummary_returnsOrderWithPayments() {
        Order o = [SELECT Id FROM Order LIMIT 1];
        PaymentService.register(o.Id, Date.today().addDays(-10), 2000, '계약금');
        PaymentService.register(o.Id, Date.today(),              3000, '중도금');

        Test.startTest();
        PaymentService.PaymentSummary s = PaymentService.getSummary(o.Id);
        Test.stopTest();

        System.assertEquals(10000, s.totalAmount);
        System.assertEquals(5000,  s.totalPaid);
        System.assertEquals(5000,  s.outstanding);
        System.assertEquals(false, s.isPaidInFull);
        System.assertEquals(2,     s.payments.size());
        // 정렬: Paid_Date DESC → 첫번째가 오늘
        System.assertEquals(Date.today(), s.payments[0].Paid_Date__c);
    }

    @IsTest
    static void testGetSummary_nullOrderId_throws() {
        assertThrows('summary null', new SummaryNullCall());
    }

    // ─── helpers ───
    private interface CallBlock { void run(); }
    private static void assertThrows(String label, CallBlock c) {
        Boolean failed = false;
        try { c.run(); } catch (AuraHandledException e) { failed = true; }
        System.assert(failed, label + ' 예외 기대');
    }
    private class ZeroCall    implements CallBlock { Id oid; ZeroCall(Id i){oid=i;}    public void run(){PaymentService.register(oid, Date.today(), 0, null);} }
    private class NegCall     implements CallBlock { Id oid; NegCall(Id i){oid=i;}     public void run(){PaymentService.register(oid, Date.today(), -100, null);} }
    private class FutureCall  implements CallBlock { Id oid; FutureCall(Id i){oid=i;}  public void run(){PaymentService.register(oid, Date.today().addDays(1), 100, null);} }
    private class NullCall    implements CallBlock {                                   public void run(){PaymentService.register(null, Date.today(), 100, null);} }
    private class SummaryNullCall implements CallBlock {                               public void run(){PaymentService.getSummary(null);} }
}
