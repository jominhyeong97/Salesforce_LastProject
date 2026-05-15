// FR-QUOTE-008: 7일 무응답 follow-up 매일 04:00 cron 등록
String jobName = 'QuoteFollowupDaily';
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :jobName]) {
    System.abortJob(ct.Id);
}
String jobId = QuoteFollowupScheduler.scheduleDaily();
System.debug('✅ Scheduled jobId=' + jobId);

System.debug('=== All Sales Cockpit scheduled jobs ===');
for (CronTrigger ct : [SELECT CronJobDetail.Name, CronExpression, State, NextFireTime
                       FROM CronTrigger
                       WHERE CronJobDetail.JobType = '7'
                       ORDER BY CronJobDetail.Name]) {
    System.debug('  ' + ct.CronJobDetail.Name + ' | ' + ct.CronExpression + ' | ' + ct.State + ' | next=' + ct.NextFireTime);
}
