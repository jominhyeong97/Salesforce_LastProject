/**
 * ShippingCompleteService — Order 출고 등록 (Day 9 #2, FR-ORDER-005/006).
 *
 * AE 가 shippingComplete LWC 의 [출고 등록] 버튼을 누르면 호출.
 *   - Production_Status 가 'Done' 일 때만 허용 (선형 상태머신: Pending→InProgress→Done→Shipped)
 *   - Shipped_Date 기록 (입력 없으면 TODAY)
 *   - Production_Status='Shipped' 갱신
 *
 * 안전 정책 — 출고 후 되돌리기 금지 (Shipped 는 terminal state).
 *
 * @group Order
 */
public with sharing class ShippingCompleteService {

    @TestVisible private static final String STATUS_DONE    = 'Done';
    @TestVisible private static final String STATUS_SHIPPED = 'Shipped';

    @AuraEnabled
    public static ShipResult markShipped(Id orderId, Date shippedDate, String note) {
        if (orderId == null) throw newAura('orderId is required');

        Order o;
        try {
            o = [
                SELECT Id, Name, Production_Status__c, Shipped_Date__c
                FROM Order WHERE Id = :orderId LIMIT 1
            ];
        } catch (QueryException e) {
            throw newAura('Order 를 찾을 수 없습니다.');
        }

        if (o.Production_Status__c == STATUS_SHIPPED) {
            throw newAura('이미 출고 완료된 주문입니다.');
        }
        if (o.Production_Status__c != STATUS_DONE) {
            throw newAura('생산 상태가 "완료" 일 때만 출고 가능합니다. 현재: ' +
                          (o.Production_Status__c == null ? '미정' : o.Production_Status__c));
        }

        Date d = (shippedDate != null) ? shippedDate : Date.today();
        if (d > Date.today()) {
            throw newAura('출고일은 미래일 수 없습니다.');
        }

        o.Production_Status__c = STATUS_SHIPPED;
        o.Shipped_Date__c      = d;
        update o;

        ShipResult r = new ShipResult();
        r.orderId = o.Id;
        r.orderName = o.Name;
        r.productionStatus = o.Production_Status__c;
        r.shippedDate = o.Shipped_Date__c;
        r.message = String.isBlank(note)
            ? '출고 등록 완료'
            : '출고 등록 완료 — ' + note;
        return r;
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    public class ShipResult {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderName;
        @AuraEnabled public String productionStatus;
        @AuraEnabled public Date shippedDate;
        @AuraEnabled public String message;
    }
}
