@IsTest
private class OrderErpSyncService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'OrderSync Test Co.',
            Business_Number__c = '100-00-00009'
        );
        insert acc;

        Id stdPb = Test.getStandardPricebookId();
        // D38 Phase 2 — EndDate 명시 (ErpServiceMock 풀 dayShift 기준)
        Date promised = Date.today().addDays(30);
        List<Order> orders = new List<Order>{
            new Order(AccountId = acc.Id, EffectiveDate = Date.today().addDays(-7),
                      EndDate = promised, Status = 'Draft', Pricebook2Id = stdPb,
                      PoNumber = 'PO-S-0006', Production_Status__c = 'InProgress'),
            new Order(AccountId = acc.Id, EffectiveDate = Date.today().addDays(-60),
                      EndDate = promised, Status = 'Draft', Pricebook2Id = stdPb,
                      PoNumber = 'PO-S-0009', Production_Status__c = 'InProgress'),
            new Order(AccountId = acc.Id, EffectiveDate = Date.today().addDays(-30),
                      EndDate = promised, Status = 'Draft', Pricebook2Id = stdPb,
                      PoNumber = 'PO-S-0002', Production_Status__c = 'Done'),
            new Order(AccountId = acc.Id, EffectiveDate = Date.today().addDays(-180),
                      EndDate = promised, Status = 'Draft', Pricebook2Id = stdPb,
                      PoNumber = 'PO-S-0003', Production_Status__c = 'Shipped')
        };
        insert orders;
    }

    @IsTest
    static void testSyncOrders_updatesRiskAndTimestamp() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-S-0006' LIMIT 1];

        Test.startTest();
        List<OrderErpSyncService.SyncOutcome> outs =
            OrderErpSyncService.syncOrders(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        Order after = [
            SELECT Delivery_Risk_Score__c, Last_ErpSync_At__c,
                   ERP_Expected_Ship_Date__c, ERP_Delay_Reason__c
            FROM Order WHERE Id = :o.Id
        ];
        System.assertNotEquals(null, after.Delivery_Risk_Score__c, '위험 점수 갱신');
        System.assertNotEquals(null, after.Last_ErpSync_At__c, '동기화 시각 갱신');
        System.assert(after.Delivery_Risk_Score__c >= 70, '끝 6 + InProgress 는 ≥70');
        // D38 Phase 2 — ERP 예상 출고일·사유 영속화
        System.assertNotEquals(null, after.ERP_Expected_Ship_Date__c,
            '위험 풀은 expectedShipDate 영속화');
        System.assertNotEquals(null, after.ERP_Delay_Reason__c,
            'delayReason 영속화');
        // 같은 Order 재동기화 → 같은 값 (결정론 검증)
        OrderErpSyncService.syncOrders(new List<Id>{ o.Id });
        Order again = [
            SELECT ERP_Expected_Ship_Date__c, ERP_Delay_Reason__c
            FROM Order WHERE Id = :o.Id
        ];
        System.assertEquals(after.ERP_Expected_Ship_Date__c, again.ERP_Expected_Ship_Date__c,
            '재동기화 시 expectedShipDate 동일 (Order.Id 해시 결정론)');
        System.assertEquals(after.ERP_Delay_Reason__c, again.ERP_Delay_Reason__c,
            '재동기화 시 delayReason 동일');
    }

    @IsTest
    static void testSyncOrders_nullThrows() {
        try {
            OrderErpSyncService.syncOrders(null);
            System.assert(false, 'null 입력은 예외');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testSyncOrders_emptyThrows() {
        try {
            OrderErpSyncService.syncOrders(new List<Id>());
            System.assert(false, '빈 입력은 예외');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testSyncAllOpen_includesShipped() {
        // D38 Phase 2: Shipped 포함 — 출고 완료 어휘 노출 위해
        Test.startTest();
        List<OrderErpSyncService.SyncOutcome> outs = OrderErpSyncService.syncAllOpen();
        Test.stopTest();

        // InProgress 2 + Done 1 + Shipped 1 = 4건
        System.assertEquals(4, outs.size(), 'Shipped 포함 4건 동기화');
        Boolean hasShipped = false;
        for (OrderErpSyncService.SyncOutcome o : outs) {
            System.assertNotEquals(null, o.riskScore);
            System.assertNotEquals(null, o.syncedAt);
            if (o.productionStatus == 'Shipped') hasShipped = true;
        }
        System.assert(hasShipped, 'Shipped Order 도 결과에 포함');
    }

    @IsTest
    static void testGetRiskView_returnsCurrent() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-S-0006' LIMIT 1];

        Test.startTest();
        OrderErpSyncService.OrderRiskView v = OrderErpSyncService.getRiskView(o.Id);
        Test.stopTest();

        System.assertEquals(o.Id, v.orderId);
        System.assertEquals('PO-S-0006', v.poNumber);
        System.assertEquals('InProgress', v.productionStatus);
        System.assertEquals('OrderSync Test Co.', v.accountName);
        // D38 Phase 2 — sync 전엔 null (영속화 안 됨)
        System.assertEquals(null, v.expectedShipDate);
        System.assertEquals(null, v.delayReason);
    }

    @IsTest
    static void testGetRiskView_returnsErpFieldsAfterSync() {
        // D38 Phase 2 — sync 후 getRiskView 가 영속화된 ERP 필드 반환
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-S-0006' LIMIT 1];

        Test.startTest();
        OrderErpSyncService.syncOrders(new List<Id>{ o.Id });
        OrderErpSyncService.OrderRiskView v = OrderErpSyncService.getRiskView(o.Id);
        Test.stopTest();

        System.assertNotEquals(null, v.expectedShipDate, 'sync 후 expectedShipDate 노출');
        System.assertNotEquals(null, v.delayReason, 'sync 후 delayReason 노출');
        System.assert(v.delayReason.contains('지연'),
            '위험 풀 사유는 "지연" 포함. actual=' + v.delayReason);
    }

    @IsTest
    static void testGetRiskView_nullThrows() {
        try {
            OrderErpSyncService.getRiskView(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testDependencyInjection_canSwapImpl() {
        // DI 검증 — Stub 구현으로 교체하여 결정적 결과 검증
        OrderErpSyncService.impl = new StubErp();
        Order o = [SELECT Id FROM Order LIMIT 1];

        Test.startTest();
        List<OrderErpSyncService.SyncOutcome> outs =
            OrderErpSyncService.syncOrders(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(42, outs[0].riskScore, 'Stub 가 42 강제');
        System.assertEquals(1, outs[0].signals.size());
        System.assertEquals('STUB', outs[0].signals[0]);
    }

    private class StubErp implements IExternalErpService {
        public List<ErpSyncResult> fetchOrderStatus(List<Id> ids) {
            List<ErpSyncResult> out = new List<ErpSyncResult>();
            for (Id i : ids) {
                ErpSyncResult r = new ErpSyncResult();
                r.orderId = i;
                r.riskScore = 42;
                r.productionStatus = 'InProgress';
                r.syncedAt = DateTime.now();
                r.signals.add('STUB');
                out.add(r);
            }
            return out;
        }
    }
}
