// ORDER-002: ERP 동기화 매일 03:00 cron 등록
String jobName = 'OrderErpSyncDaily';
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :jobName]) {
    System.abortJob(ct.Id);
}
String jobId = OrderErpSyncScheduler.scheduleDaily();
System.debug('✅ Scheduled jobId=' + jobId);

for (CronTrigger ct : [SELECT CronJobDetail.Name, CronExpression, State, NextFireTime FROM CronTrigger WHERE Id = :jobId]) {
    System.debug('Verified: ' + ct.CronJobDetail.Name + ' cron=' + ct.CronExpression + ' state=' + ct.State + ' next=' + ct.NextFireTime);
}

// 전체 active job 확인
System.debug('=== All active scheduled jobs ===');
for (CronTrigger ct : [SELECT CronJobDetail.Name, CronExpression, State, NextFireTime
                       FROM CronTrigger
                       WHERE CronJobDetail.JobType = '7'  // Scheduled Apex
                       ORDER BY CronJobDetail.Name]) {
    System.debug('  ' + ct.CronJobDetail.Name + ' | ' + ct.CronExpression + ' | ' + ct.State + ' | next=' + ct.NextFireTime);
}
