/**
 * OrderErpSyncService — Day 8 ERP 동기화 진입점.
 *
 * 책임 — LWC/Cockpit 의 [🔄 ERP 동기화] 버튼을 받아
 *   1) IExternalErpService.fetchOrderStatus() 호출 (Mock 또는 실 ERP 어댑터)
 *   2) Order.Delivery_Risk_Score__c + Last_ErpSync_At__c 갱신
 *   3) LWC 노출용 SyncOutcome 반환
 *
 * 안전 정책 (D26 일관) — Order 가격·수량·라인 직접 변경 금지.
 * 위험 점수·동기화 시각만 갱신, AE 가 후속 액션(사전 통보 메일 등) 결정.
 *
 * @group Order
 */
public with sharing class OrderErpSyncService {

    @TestVisible static IExternalErpService impl = new ErpServiceMock();

    /** 단일/다중 Order 동기화. LWC orderRiskCard 가 호출. */
    @AuraEnabled
    public static List<SyncOutcome> syncOrders(List<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            throw new AuraHandledException('orderIds is required');
        }

        List<ErpSyncResult> results = impl.fetchOrderStatus(orderIds);
        if (results.isEmpty()) return new List<SyncOutcome>();

        DateTime now = DateTime.now();
        List<Order> toUpdate = new List<Order>();
        for (ErpSyncResult r : results) {
            toUpdate.add(new Order(
                Id                          = r.orderId,
                Delivery_Risk_Score__c      = r.riskScore,
                Last_ErpSync_At__c          = now,
                ERP_Expected_Ship_Date__c   = r.expectedShipDate, // D38 Phase 2
                ERP_Delay_Reason__c         = r.delayReason       // D38 Phase 2
            ));
        }
        update toUpdate;

        List<SyncOutcome> out = new List<SyncOutcome>();
        for (ErpSyncResult r : results) {
            SyncOutcome o = new SyncOutcome();
            o.orderId          = r.orderId;
            o.riskScore        = r.riskScore;
            o.productionStatus = r.productionStatus;
            o.syncedAt          = now;
            o.signals          = r.signals;
            o.expectedShipDate = r.expectedShipDate;  // D38 Phase 2
            o.delayReason      = r.delayReason;       // D38 Phase 2
            out.add(o);
        }
        return out;
    }

    /** 콕피트용 — 활성 Order(InProgress/Pending/Done/Shipped) 일괄 동기화.
     *  D38 Phase 2: Shipped 포함 — ERP 측 "출고 완료" 어휘를 시연에 노출. */
    @AuraEnabled
    public static List<SyncOutcome> syncAllOpen() {
        List<Id> ids = new List<Id>();
        for (Order o : [
            SELECT Id
            FROM Order
            WHERE Production_Status__c IN ('InProgress', 'Pending', 'Done', 'Shipped')
            ORDER BY EffectiveDate ASC
            LIMIT 200
        ]) {
            ids.add(o.Id);
        }
        if (ids.isEmpty()) return new List<SyncOutcome>();
        return syncOrders(ids);
    }

    /** 단일 Order 위험 정보 조회 (LWC @wire 용). 동기화 없이 현재 저장 값만 반환. */
    @AuraEnabled(cacheable=true)
    public static OrderRiskView getRiskView(Id orderId) {
        if (orderId == null) {
            throw new AuraHandledException('orderId is required');
        }
        Order o = [
            SELECT Id, Name, PoNumber, Production_Status__c,
                   Delivery_Risk_Score__c, Last_ErpSync_At__c, EndDate, Account.Name,
                   ERP_Expected_Ship_Date__c, ERP_Delay_Reason__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        OrderRiskView v = new OrderRiskView();
        v.orderId          = o.Id;
        v.orderName        = o.Name;
        v.poNumber         = o.PoNumber;
        v.productionStatus = o.Production_Status__c;
        v.riskScore        = (Integer) o.Delivery_Risk_Score__c;
        v.lastErpSyncAt    = o.Last_ErpSync_At__c;
        v.accountName      = (o.Account != null) ? o.Account.Name : null;
        v.endDate          = o.EndDate;
        v.dueLabel         = AeCockpitService.dueLabel(o.EndDate);
        v.expectedShipDate = o.ERP_Expected_Ship_Date__c;  // D38 Phase 2
        v.delayReason      = o.ERP_Delay_Reason__c;        // D38 Phase 2
        return v;
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs (@AuraEnabled — LWC 노출용)
    // ─────────────────────────────────────────────────────────────────────

    public class SyncOutcome {
        @AuraEnabled public Id orderId;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String productionStatus;
        @AuraEnabled public DateTime syncedAt;
        @AuraEnabled public List<String> signals;
        @AuraEnabled public Date expectedShipDate;  // D38 Phase 2
        @AuraEnabled public String delayReason;     // D38 Phase 2
    }

    public class OrderRiskView {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderName;
        @AuraEnabled public String poNumber;
        @AuraEnabled public String productionStatus;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public DateTime lastErpSyncAt;
        @AuraEnabled public String accountName;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String dueLabel;
        @AuraEnabled public Date expectedShipDate;  // D38 Phase 2
        @AuraEnabled public String delayReason;     // D38 Phase 2
    }
}
