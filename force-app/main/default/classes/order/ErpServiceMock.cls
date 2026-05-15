/**
 * ErpServiceMock — Day 8 시연용 IExternalErpService 구현.
 *
 * D17-정정 (2026-05-08) 시드 규약과 정합:
 *   PoNumber 끝 '6' + InProgress → 위험        riskScore 70~84  (5건)
 *   PoNumber 끝 '9' + InProgress → 대형지연    riskScore 85~97  (5건)
 *   기타 InProgress              → 진행중 정상  riskScore 20~39
 *   Done                          → 출고 대기   riskScore  5~14
 *   Shipped                       → 출고 완료   riskScore  0~ 7
 *   Pending                       → 생산 대기   riskScore 25~39
 *
 * D38 Phase 2 (2026-05-12) — ERP 예상 출고일·사유 풀 기반 결정론.
 *   분기별 (날짜·사유) 풀에서 hash(Order.Id) % 풀크기 로 선택.
 *   같은 Order 는 매 동기화마다 같은 결과 (Order.Id 해시 결정론).
 *   풀 크기와 구성을 조정해 시연 분포 제어 가능.
 *
 * @group Order
 */
public with sharing class ErpServiceMock implements IExternalErpService {

    /** 풀 항목 — 날짜(null=미정) + 한국어 사유. */
    @TestVisible
    public class Forecast {
        public Integer dayShift;   // EndDate 기준 일 shift (null = 출고일 미정)
        public String reason;
        public Forecast(Integer dayShift, String reason) {
            this.dayShift = dayShift;
            this.reason = reason;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 분기별 풀 (D38 Phase 2)
    // ─────────────────────────────────────────────────────────────────────

    private static final List<Forecast> POOL_HIGH_RISK = new List<Forecast>{
        new Forecast(3, '생산 라인 정체 — D+3 지연'),
        new Forecast(5, '자재 부분 지연 — D+5 지연'),
        new Forecast(7, '품질 재검사 — D+7 지연')
    };

    private static final List<Forecast> POOL_CRITICAL = new List<Forecast>{
        new Forecast(null, '미생산 — 자재 미투입'),
        new Forecast(null, '미생산 — 생산 라인 정체'),
        new Forecast(null, '미출고 — 포장 대기'),
        new Forecast(null, '미출고 — 배송 차량 미배차'),
        new Forecast(null, '출고 보류 — 품질 검사 재진행'),
        new Forecast(14,   '재계획 — D+14 지연')
    };

    private static final List<Forecast> POOL_INPROGRESS_OK = new List<Forecast>{
        new Forecast(0,  '정시 진행'),
        new Forecast(-1, '조기 진행 — D-1'),
        new Forecast(1,  'D+1 소폭 지연')
    };

    private static final List<Forecast> POOL_DONE = new List<Forecast>{
        new Forecast(-2, '생산 완료 — 출고 대기'),
        new Forecast(-1, '생산 완료 — 익일 출고 예정'),
        new Forecast(0,  '생산 완료 — 당일 출고 예정')
    };

    private static final List<Forecast> POOL_SHIPPED = new List<Forecast>{
        new Forecast(-3, '출고 완료 — 3일 전 출하'),
        new Forecast(-5, '출고 완료 — 5일 전 출하'),
        new Forecast(-7, '출고 완료 — 7일 전 출하')
    };

    private static final List<Forecast> POOL_PENDING = new List<Forecast>{
        new Forecast(null, '자재 준비 중 — 입고 대기'),
        new Forecast(null, '생산 일정 미확정'),
        new Forecast(0,    '생산 일정 확정 — 약속일 진입 예정')
    };

    // ─────────────────────────────────────────────────────────────────────
    // 진입점
    // ─────────────────────────────────────────────────────────────────────

    public List<ErpSyncResult> fetchOrderStatus(List<Id> orderIds) {
        List<ErpSyncResult> out = new List<ErpSyncResult>();
        if (orderIds == null || orderIds.isEmpty()) return out;

        DateTime now = DateTime.now();
        for (Order o : [
            SELECT Id, PoNumber, Production_Status__c, EndDate
            FROM Order
            WHERE Id IN :orderIds
        ]) {
            ErpSyncResult r = new ErpSyncResult();
            r.orderId          = o.Id;
            r.productionStatus = o.Production_Status__c;
            r.syncedAt         = now;

            String poEnd      = lastChar(o.PoNumber);
            String prodStatus = o.Production_Status__c;
            List<Forecast> pool;

            if (poEnd == '6' && prodStatus == 'InProgress') {
                r.riskScore = 70 + jitter(o.Id, 15);
                pool = POOL_HIGH_RISK;
                r.signals.add('고객 사전 통보 권고');
            } else if (poEnd == '9' && prodStatus == 'InProgress') {
                r.riskScore = 85 + jitter(o.Id, 13);
                pool = POOL_CRITICAL;
                r.signals.add('즉시 고객 통보 + AE 직접 콜 필요');
            } else if (prodStatus == 'InProgress') {
                r.riskScore = 20 + jitter(o.Id, 20);
                pool = POOL_INPROGRESS_OK;
            } else if (prodStatus == 'Done') {
                r.riskScore = 5 + jitter(o.Id, 10);
                pool = POOL_DONE;
            } else if (prodStatus == 'Shipped') {
                r.riskScore = jitter(o.Id, 8);
                pool = POOL_SHIPPED;
            } else {
                r.riskScore = 25 + jitter(o.Id, 15); // Pending or null
                pool = POOL_PENDING;
            }

            Forecast f = pick(pool, o.Id);
            applyForecast(r, f, o.EndDate);
            out.add(r);
        }
        return out;
    }

    // ─────────────────────────────────────────────────────────────────────
    // helpers
    // ─────────────────────────────────────────────────────────────────────

    /** 결정론적 풀 선택 — hash(Order.Id) % size. */
    @TestVisible
    private static Forecast pick(List<Forecast> pool, Id recordId) {
        Integer idx = Math.mod(Math.abs(String.valueOf(recordId).hashCode()), pool.size());
        return pool[idx];
    }

    /** 풀 결과를 ErpSyncResult 에 사상 — expectedShipDate / delayReason / signals. */
    @TestVisible
    private static void applyForecast(ErpSyncResult r, Forecast f, Date endDate) {
        r.delayReason = f.reason;

        String msg;
        if (f.dayShift == null || endDate == null) {
            r.expectedShipDate = null;
            msg = 'ERP 예상 출고: 미정 — ' + f.reason;
        } else {
            Date eta = endDate.addDays(f.dayShift);
            r.expectedShipDate = eta;
            String etaText = String.valueOf(eta);
            if (f.dayShift == 0) {
                msg = 'ERP 예상 출고: ' + etaText + ' (약속과 동일)';
            } else if (f.dayShift > 0) {
                msg = 'ERP 예상 출고: ' + etaText
                    + ' (약속 ' + String.valueOf(endDate) + ' → D+' + f.dayShift + ' 지연)';
            } else {
                msg = 'ERP 예상 출고: ' + etaText
                    + ' (약속 ' + String.valueOf(endDate) + ' → D' + f.dayShift + ' 조기)';
            }
        }

        // 빈 list 에 add(0, ...) 는 Apex 에서 throw → prepend 안전 패턴
        List<String> merged = new List<String>{ msg };
        if (r.signals != null) merged.addAll(r.signals);
        r.signals = merged;
    }

    @TestVisible
    private static String lastChar(String s) {
        return (s != null && s.length() > 0) ? s.substring(s.length() - 1) : '';
    }

    @TestVisible
    private static Integer jitter(Id recordId, Integer range) {
        if (range <= 0) return 0;
        Integer h = Math.abs(String.valueOf(recordId).hashCode());
        return Math.mod(h, range);
    }
}
