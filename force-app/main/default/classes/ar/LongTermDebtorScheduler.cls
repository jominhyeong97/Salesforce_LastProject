/**
 * LongTermDebtorScheduler — 매일 새벽 Account.Long_Term_Debtor__c 재계산 (Day 9 #5, FR-AR-002).
 *
 * 룰: Outstanding_Amount__c > 0 AND EffectiveDate <= today - 180 인 Order 를 보유한 Account 는
 *      Long_Term_Debtor=true, 아니면 false.
 *
 * D20 일관 — Flow XML 대신 Schedulable Apex (테스트·디버깅·bulkify 우월).
 * 활성화: Setup → Apex Classes → "LongTermDebtorScheduler" → Schedule Apex.
 *          또는 한 번만: System.schedule('LongTermDebtorDaily', '0 0 2 * * ?', new LongTermDebtorScheduler());
 *
 * @group AR
 */
public with sharing class LongTermDebtorScheduler implements Schedulable {

    @TestVisible public static final Integer THRESHOLD_DAYS = 180;

    public void execute(SchedulableContext sc) {
        process();
    }

    /** AE 가 수동 실행 가능 / 데모용. 변경된 Account 수 반환. */
    @AuraEnabled
    public static Integer process() {
        Date cutoff = Date.today().addDays(-THRESHOLD_DAYS);

        // 1. 장기 미수금 보유 Account 식별
        Set<Id> longTermAccountIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT AccountId aid
            FROM Order
            WHERE Outstanding_Amount__c > 0
              AND EffectiveDate <= :cutoff
              AND AccountId != null
            GROUP BY AccountId
        ]) {
            longTermAccountIds.add((Id) ar.get('aid'));
        }

        // 2. Long_Term_Debtor=true 인 모든 Account + 신규 식별 Account 통합 검토
        List<Account> toUpdate = new List<Account>();
        for (Account a : [
            SELECT Id, Long_Term_Debtor__c
            FROM Account
            WHERE Long_Term_Debtor__c = true OR Id IN :longTermAccountIds
        ]) {
            Boolean newFlag = longTermAccountIds.contains(a.Id);
            if ((a.Long_Term_Debtor__c == true) != newFlag) {
                a.Long_Term_Debtor__c = newFlag;
                toUpdate.add(a);
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        return toUpdate.size();
    }

    /** 데모 편의 — 매일 새벽 2시 스케줄 등록. */
    public static String scheduleDaily() {
        String jobId = System.schedule(
            'LongTermDebtorDaily',
            '0 0 2 * * ?',
            new LongTermDebtorScheduler()
        );
        return jobId;
    }
}
