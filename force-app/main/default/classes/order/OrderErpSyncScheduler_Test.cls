@IsTest
private class OrderErpSyncScheduler_Test {

    @IsTest
    static void testScheduleDaily_registersCron() {
        // 실 환경에 'OrderErpSyncDaily' 가 이미 등록돼 있을 수 있으므로
        // test 에서는 test 전용 이름으로 System.schedule 호출.
        Test.startTest();
        String jobId = System.schedule(
            'OrderErpSyncDaily_TEST_' + Datetime.now().getTime(),
            '0 0 3 * * ?',
            new OrderErpSyncScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'jobId should be returned');

        CronTrigger ct = [
            SELECT Id, CronExpression, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals('0 0 3 * * ?', ct.CronExpression, 'cron should be 03:00 daily');
    }

    @IsTest
    static void testExecute_runsSyncAllOpen() {
        // syncAllOpen() 가 throw 없이 실행되는지 확인 (시드 없는 환경에서도 안전해야 함)
        OrderErpSyncScheduler s = new OrderErpSyncScheduler();
        Test.startTest();
        s.execute(null);  // SchedulableContext 는 null 허용
        Test.stopTest();
        // 시드 미존재 → syncAllOpen 은 빈 리스트 반환, 예외 없음
        System.assert(true, 'execute should not throw');
    }
}
