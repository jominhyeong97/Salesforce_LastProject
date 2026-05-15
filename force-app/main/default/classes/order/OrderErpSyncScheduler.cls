/**
 * OrderErpSyncScheduler — Day 8 ERP 동기화 자동화 (FR-ORDER-002).
 *
 * 책임: 매일 새벽 03:00 미출고 Order 일괄 ERP 동기화 (OrderErpSyncService.syncAllOpen 위임).
 *   D17 일관 — Apex Mock 격리 게이트웨이 패턴. 외부 callout 0.
 *
 * 등록: 한 번만 — Anonymous Apex
 *   OrderErpSyncScheduler.scheduleDaily();
 *
 * @group Order
 */
public with sharing class OrderErpSyncScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        OrderErpSyncService.syncAllOpen();
    }

    /** 데모 편의 — 매일 새벽 3시 스케줄 등록. */
    public static String scheduleDaily() {
        return System.schedule(
            'OrderErpSyncDaily',
            '0 0 3 * * ?',
            new OrderErpSyncScheduler()
        );
    }
}
