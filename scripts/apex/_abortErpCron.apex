List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name FROM CronTrigger WHERE CronJobDetail.Name LIKE '%ErpSync%' OR Id = '08edM00000i7lIl'];
for (CronTrigger j : jobs) {
    System.debug('Aborting: ' + j.Id + ' / ' + j.CronJobDetail.Name);
    System.abortJob(j.Id);
}
System.debug('Aborted ' + jobs.size() + ' jobs.');
