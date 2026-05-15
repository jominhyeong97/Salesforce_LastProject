// Phase 2: LongTermDebtorScheduler 매일 02:00 cron 등록 (FR-AR-002)
// 멱등성 — 동일 이름 job 있으면 abort 후 재등록

String jobName = 'LongTermDebtorDaily';
List<CronTrigger> existing = [
    SELECT Id, CronJobDetail.Name, State, NextFireTime
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
];
for (CronTrigger ct : existing) {
    System.debug('Existing job found: ' + ct.CronJobDetail.Name + ' state=' + ct.State + ' next=' + ct.NextFireTime + ' → abort');
    System.abortJob(ct.Id);
}

String jobId = LongTermDebtorScheduler.scheduleDaily();
System.debug('✅ Scheduled jobId=' + jobId);

// 검증
List<CronTrigger> ctrs = [
    SELECT Id, CronJobDetail.Name, CronExpression, State, NextFireTime, TimesTriggered
    FROM CronTrigger
    WHERE Id = :jobId
];
for (CronTrigger ct : ctrs) {
    System.debug('Verified: name=' + ct.CronJobDetail.Name + ' cron=' + ct.CronExpression + ' state=' + ct.State + ' next=' + ct.NextFireTime);
}
