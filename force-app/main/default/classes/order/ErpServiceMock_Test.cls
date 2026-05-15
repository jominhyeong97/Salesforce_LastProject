@IsTest
private class ErpServiceMock_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'ERP Mock Test Co.',
            Business_Number__c = '100-00-00009'
        );
        insert acc;

        Id stdPb = Test.getStandardPricebookId();

        // PoNumber 끝자리 + Production_Status 6개 조합
        List<Order> orders = new List<Order>();
        orders.add(buildOrder(acc.Id, stdPb, 'PO-T-0006', 'InProgress'));  // 위험
        orders.add(buildOrder(acc.Id, stdPb, 'PO-T-0009', 'InProgress'));  // 대형지연
        orders.add(buildOrder(acc.Id, stdPb, 'PO-T-0001', 'InProgress'));  // 진행중 정상
        orders.add(buildOrder(acc.Id, stdPb, 'PO-T-0002', 'Done'));        // 출고대기
        orders.add(buildOrder(acc.Id, stdPb, 'PO-T-0003', 'Shipped'));     // 출고완료
        orders.add(buildOrder(acc.Id, stdPb, 'PO-T-0004', 'Pending'));     // 생산대기
        insert orders;
    }

    private static Order buildOrder(Id accId, Id pbId, String poNum, String prodStatus) {
        return new Order(
            AccountId = accId,
            EffectiveDate = Date.today().addDays(-7),
            EndDate = Date.today().addDays(30), // D38 Phase 2 — 약속 납기일 (풀 dayShift 기준)
            Status = 'Draft',
            Pricebook2Id = pbId,
            PoNumber = poNum,
            Production_Status__c = prodStatus
        );
    }

    @IsTest
    static void testHighRisk_PoEnd6_InProgress() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0006' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(1, rs.size());
        ErpSyncResult r = rs[0];
        System.assert(r.riskScore >= 70 && r.riskScore <= 84,
            '끝 6 + InProgress → 70~84. actual=' + r.riskScore);
        System.assert(!r.signals.isEmpty(), '진단 신호 비어있지 않음');
        // D38 Phase 2 — 위험 풀은 모두 구체 날짜 (D+3/+5/+7)
        System.assertNotEquals(null, r.expectedShipDate, '위험 풀은 expectedShipDate not null');
        System.assert(r.expectedShipDate > Date.today().addDays(30),
            '위험 풀은 약속(D=today+30) 이후로 지연. actual=' + r.expectedShipDate);
        System.assertNotEquals(null, r.delayReason);
        System.assert(r.delayReason.contains('지연'),
            'delayReason 에 "지연" 포함. actual=' + r.delayReason);
    }

    @IsTest
    static void testCriticalDelay_PoEnd9_InProgress() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0009' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        ErpSyncResult r = rs[0];
        System.assert(r.riskScore >= 85 && r.riskScore <= 97,
            '끝 9 + InProgress → 85~97. actual=' + r.riskScore);
        // D38 Phase 2 — 대형지연 풀: 미정(null) 5건 + D+14 1건 → 풀 크기 6
        System.assertNotEquals(null, r.delayReason);
        Boolean isCritical = r.delayReason.contains('미생산')
            || r.delayReason.contains('미출고')
            || r.delayReason.contains('출고 보류')
            || r.delayReason.contains('재계획');
        System.assert(isCritical,
            '대형지연 풀 사유. actual=' + r.delayReason);
        System.assert(String.join(r.signals, ' ').contains('즉시'),
            '즉시 통보 권고 신호 포함');
    }

    @IsTest
    static void testInProgress_otherDigit_midRisk() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0001' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        ErpSyncResult r = rs[0];
        System.assert(r.riskScore >= 20 && r.riskScore <= 39,
            '끝 1 + InProgress → 20~39. actual=' + r.riskScore);
        // D38 Phase 2 — 진행중 정상 풀 = [-1, 0, +1] 모두 구체 날짜
        System.assertNotEquals(null, r.expectedShipDate);
        System.assertNotEquals(null, r.delayReason);
    }

    @IsTest
    static void testDone_lowRisk() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0002' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        ErpSyncResult r = rs[0];
        System.assert(r.riskScore >= 5 && r.riskScore <= 14,
            'Done → 5~14. actual=' + r.riskScore);
        System.assertNotEquals(null, r.expectedShipDate);
        System.assert(r.delayReason.contains('생산 완료'),
            'Done 풀 사유 "생산 완료" 포함. actual=' + r.delayReason);
    }

    @IsTest
    static void testShipped_minimalRisk() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0003' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        ErpSyncResult r = rs[0];
        System.assert(r.riskScore >= 0 && r.riskScore <= 7,
            'Shipped → 0~7. actual=' + r.riskScore);
        System.assertNotEquals(null, r.expectedShipDate, 'Shipped 풀은 이전 날짜로 구체화');
        System.assert(r.delayReason.contains('출고 완료'),
            'Shipped 풀 사유 "출고 완료" 포함. actual=' + r.delayReason);
    }

    @IsTest
    static void testPending_lowMidRisk() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0004' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        ErpSyncResult r = rs[0];
        System.assert(r.riskScore >= 25 && r.riskScore <= 39,
            'Pending → 25~39. actual=' + r.riskScore);
        // Pending 풀 = [null, null, 0] — 미정 2건 + 확정 1건
        System.assertNotEquals(null, r.delayReason);
    }

    @IsTest
    static void testEmptyInput_returnsEmpty() {
        ErpServiceMock svc = new ErpServiceMock();
        System.assertEquals(0, svc.fetchOrderStatus(null).size());
        System.assertEquals(0, svc.fetchOrderStatus(new List<Id>()).size());
    }

    @IsTest
    static void testDeterminism_sameOrderSameScore() {
        Order o = [SELECT Id FROM Order WHERE PoNumber = 'PO-T-0006' LIMIT 1];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs1 = svc.fetchOrderStatus(new List<Id>{ o.Id });
        List<ErpSyncResult> rs2 = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        System.assertEquals(rs1[0].riskScore, rs2[0].riskScore,
            '같은 Order 는 결정적으로 같은 점수');
        // D38 Phase 2 — 풀 선택도 결정적
        System.assertEquals(rs1[0].expectedShipDate, rs2[0].expectedShipDate,
            '같은 Order 는 결정적으로 같은 expectedShipDate');
        System.assertEquals(rs1[0].delayReason, rs2[0].delayReason,
            '같은 Order 는 결정적으로 같은 delayReason');
    }

    @IsTest
    static void testBulk_processesAll() {
        List<Order> all = [SELECT Id FROM Order];
        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>(new Map<Id,Order>(all).keySet()));
        Test.stopTest();

        System.assertEquals(6, rs.size(), '6 Order 모두 처리');
        for (ErpSyncResult r : rs) {
            System.assertNotEquals(null, r.riskScore);
            System.assertNotEquals(null, r.syncedAt);
            System.assertNotEquals(null, r.delayReason, '모든 풀은 사유 명시');
        }
    }

    @IsTest
    static void testForecast_endDateNull_undecided() {
        // D38 Phase 2 — Order.EndDate null 이면 expectedShipDate 도 null (사유는 풀 항목 그대로)
        Account a = [SELECT Id FROM Account LIMIT 1];
        Id stdPb = Test.getStandardPricebookId();
        Order o = new Order(
            AccountId = a.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPb,
            PoNumber = 'PO-NULL-EndDate-0006',
            Production_Status__c = 'InProgress'
            // EndDate 명시 null
        );
        insert o;

        ErpServiceMock svc = new ErpServiceMock();

        Test.startTest();
        List<ErpSyncResult> rs = svc.fetchOrderStatus(new List<Id>{ o.Id });
        Test.stopTest();

        ErpSyncResult r = rs[0];
        System.assertEquals(null, r.expectedShipDate,
            'EndDate null 이면 expectedShipDate null');
        System.assertNotEquals(null, r.delayReason, '사유는 그대로 명시');
        Boolean undecidedSignal = false;
        for (String s : r.signals) {
            if (s.contains('미정')) { undecidedSignal = true; break; }
        }
        System.assert(undecidedSignal, 'EndDate null 시 signals 첫 줄에 "미정" 포함');
    }
}
