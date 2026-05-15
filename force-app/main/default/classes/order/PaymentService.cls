/**
 * PaymentService — 분할 입금 등록 + Order.Total_Paid_Amount 자동 합산 (Day 9 #3, FR-AR-001).
 *
 *  - Order 가 Master-Detail 가 아니므로 Roll-Up Summary 불가 → Apex 가 누적 계산
 *  - 입금 등록 시 같은 Order 의 Status='Paid' Payment 합을 재계산해 Order.Total_Paid_Amount__c 갱신
 *  - Account.Total_AR__c 도 동일 패턴으로 Account 의 모든 Order Outstanding 합계 재계산
 *
 *  Outstanding_Amount__c (Formula) 는 자동 차감 — Apex 가 손대지 않음.
 *
 * @group Order
 */
public with sharing class PaymentService {

    @TestVisible private static final String PAID = 'Paid';

    @AuraEnabled
    public static PaymentResult register(Id orderId, Date paidDate, Decimal amount, String memo) {
        if (orderId == null)               throw newAura('orderId is required');
        if (amount == null || amount <= 0) throw newAura('입금액은 0 보다 커야 합니다.');
        Date d = (paidDate != null) ? paidDate : Date.today();
        if (d > Date.today())              throw newAura('입금일은 미래일 수 없습니다.');

        Order o;
        try {
            o = [
                SELECT Id, AccountId, TotalAmount, Total_Paid_Amount__c
                FROM Order WHERE Id = :orderId LIMIT 1
            ];
        } catch (QueryException e) {
            throw newAura('Order 를 찾을 수 없습니다.');
        }

        Payment__c p = new Payment__c(
            Order__c       = orderId,
            Paid_Date__c   = d,
            Paid_Amount__c = amount,
            Status__c      = PAID,
            Memo__c        = memo
        );
        insert p;

        recalcOrderTotalPaid(orderId);
        if (o.AccountId != null) recalcAccountTotalAR(o.AccountId);

        Order reload = [
            SELECT Total_Paid_Amount__c, Outstanding_Amount__c, TotalAmount
            FROM Order WHERE Id = :orderId LIMIT 1
        ];
        PaymentResult r = new PaymentResult();
        r.paymentId   = p.Id;
        r.orderId     = orderId;
        r.paidAmount  = amount;
        r.totalPaid   = nz(reload.Total_Paid_Amount__c);
        r.outstanding = nz(reload.Outstanding_Amount__c);
        r.totalAmount = nz(reload.TotalAmount);
        return r;
    }

    @AuraEnabled(cacheable=true)
    public static PaymentSummary getSummary(Id orderId) {
        if (orderId == null) throw newAura('orderId is required');

        Order o;
        try {
            o = [
                SELECT Id, Name, AccountId, TotalAmount,
                       Total_Paid_Amount__c, Outstanding_Amount__c
                FROM Order WHERE Id = :orderId LIMIT 1
            ];
        } catch (QueryException e) {
            throw newAura('Order 를 찾을 수 없습니다.');
        }

        List<Payment__c> payments = [
            SELECT Id, Paid_Date__c, Paid_Amount__c, Status__c, Memo__c
            FROM Payment__c
            WHERE Order__c = :orderId
            ORDER BY Paid_Date__c DESC, CreatedDate DESC
        ];

        PaymentSummary s = new PaymentSummary();
        s.orderId     = o.Id;
        s.orderName   = o.Name;
        s.totalAmount = nz(o.TotalAmount);
        s.totalPaid   = nz(o.Total_Paid_Amount__c);
        s.outstanding = nz(o.Outstanding_Amount__c);
        s.payments    = payments;
        s.isPaidInFull = s.outstanding <= 0 && s.totalAmount > 0;
        return s;
    }

    // ─────────────────────────────────────────────────────────────────────
    // helpers
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static void recalcOrderTotalPaid(Id orderId) {
        Decimal sum = 0;
        for (AggregateResult ar : [
            SELECT SUM(Paid_Amount__c) total FROM Payment__c
            WHERE Order__c = :orderId AND Status__c = :PAID
        ]) {
            sum = nz((Decimal) ar.get('total'));
        }
        update new Order(Id = orderId, Total_Paid_Amount__c = sum);
    }

    @TestVisible
    private static void recalcAccountTotalAR(Id accountId) {
        Decimal sum = 0;
        for (AggregateResult ar : [
            SELECT SUM(Outstanding_Amount__c) total FROM Order
            WHERE AccountId = :accountId
        ]) {
            sum = nz((Decimal) ar.get('total'));
        }
        if (sum < 0) sum = 0;
        update new Account(Id = accountId, Total_AR__c = sum);
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs
    // ─────────────────────────────────────────────────────────────────────

    public class PaymentResult {
        @AuraEnabled public Id paymentId;
        @AuraEnabled public Id orderId;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public Decimal totalPaid;
        @AuraEnabled public Decimal outstanding;
        @AuraEnabled public Decimal totalAmount;
    }

    public class PaymentSummary {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderName;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal totalPaid;
        @AuraEnabled public Decimal outstanding;
        @AuraEnabled public Boolean isPaidInFull;
        @AuraEnabled public List<Payment__c> payments;
    }
}
