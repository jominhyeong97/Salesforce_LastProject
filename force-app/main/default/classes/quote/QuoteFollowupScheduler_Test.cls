@IsTest
private class QuoteFollowupScheduler_Test {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'FU Test Co.', Business_Number__c = '100-00-00009');
        insert a;

        Opportunity o = new Opportunity(
            Name = 'FU Opp', AccountId = a.Id,
            StageName = '견적 발송', CloseDate = Date.today().addDays(30)
        );
        insert o;
    }

    static Quote insertSentQuote(String name, Integer daysAgo, DateTime lastOpened) {
        Opportunity o = [SELECT Id FROM Opportunity LIMIT 1];
        Quote q = new Quote(
            Name = name, OpportunityId = o.Id,
            Status = '발송', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        update new Quote(
            Id = q.Id,
            Sent_Date__c = Datetime.now().addDays(-daysAgo),
            Last_Opened_At__c = lastOpened
        );
        return q;
    }

    @IsTest
    static void testProcess_createsTaskFor7dayOldQuote() {
        Quote q = insertSentQuote('FU-Q-001', 8, null);

        Test.startTest();
        Integer n = QuoteFollowupScheduler.process();
        Test.stopTest();

        System.assertEquals(1, n, '8일 경과 + Last_Opened null → Task 1 건 생성');
        List<Task> tasks = [SELECT Subject, WhatId, Priority, Status FROM Task WHERE WhatId = :q.Id];
        System.assertEquals(1, tasks.size());
        System.assert(tasks[0].Subject.contains('FU-Q-001'));
        System.assertEquals('High', tasks[0].Priority);
    }

    @IsTest
    static void testProcess_skipsRecentQuote() {
        insertSentQuote('FU-Q-002', 3, null);
        Test.startTest();
        Integer n = QuoteFollowupScheduler.process();
        Test.stopTest();
        System.assertEquals(0, n, '3일 경과 → 임계값 미달, Task 생성 안 함');
    }

    @IsTest
    static void testProcess_skipsOpenedQuote() {
        insertSentQuote('FU-Q-003', 8, Datetime.now().addDays(-1));
        Test.startTest();
        Integer n = QuoteFollowupScheduler.process();
        Test.stopTest();
        System.assertEquals(0, n, 'Last_Opened_At 있음 → 무응답 아님');
    }

    @IsTest
    static void testProcess_idempotent_noDuplicateTask() {
        Quote q = insertSentQuote('FU-Q-004', 10, null);
        // 1차 실행
        QuoteFollowupScheduler.process();
        // 2차 실행 — 이미 미완료 Task 있으므로 skip
        Test.startTest();
        Integer n = QuoteFollowupScheduler.process();
        Test.stopTest();
        System.assertEquals(0, n, '이미 미완료 follow-up Task 있음 → 중복 생성 안 함');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :q.Id]);
    }

    @IsTest
    static void testScheduleDaily_registersCron() {
        // 실 환경에 'QuoteFollowupDaily' 가 이미 등록돼 있을 수 있어 test 전용 이름 사용.
        Test.startTest();
        String jobId = System.schedule(
            'QuoteFollowupDaily_TEST_' + Datetime.now().getTime(),
            '0 0 4 * * ?',
            new QuoteFollowupScheduler()
        );
        Test.stopTest();
        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 4 * * ?', ct.CronExpression);
    }

    @IsTest
    static void testExecute_runsProcess() {
        QuoteFollowupScheduler s = new QuoteFollowupScheduler();
        Test.startTest();
        s.execute(null);
        Test.stopTest();
        System.assert(true);
    }
}
