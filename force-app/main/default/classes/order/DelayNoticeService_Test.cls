@IsTest
private class DelayNoticeService_Test {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = '지연테스트', Business_Number__c = '100-00-00009');
        insert a;
        Id stdPb = Test.getStandardPricebookId();
        Order o = new Order(
            AccountId = a.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPb,
            PoNumber = 'PO-TEST-1',
            Production_Status__c = 'InProgress',
            Delivery_Risk_Score__c = 80
        );
        insert o;
    }

    @IsTest
    static void testDraft_aiSuccess() {
        DelayNoticeInvoker.mockJsonResponse =
            '{"subject":"[한도정밀] PO-TEST-1 납기 지연 사전 통보","body":"지연테스트 담당자님,\\n안녕하세요. 한도정밀 영업팀입니다."}';
        Order o = [SELECT Id FROM Order LIMIT 1];

        Test.startTest();
        DelayNoticeService.Draft d = DelayNoticeService.draft(o.Id, '라인 점검 중');
        Test.stopTest();

        System.assertEquals('ai', d.aiSource);
        System.assert(d.subject.contains('PO-TEST-1'));
        System.assert(d.body.contains('지연테스트'));
        System.assertEquals('지연테스트', d.accountName);
        System.assertEquals('PO-TEST-1', d.orderRef);
        System.assertEquals(80, d.riskScore);
    }

    @IsTest
    static void testDraft_codeFenceStripped() {
        DelayNoticeInvoker.mockJsonResponse =
            '```json\n{"subject":"[한도정밀] PO-TEST-1","body":"본문"}\n```';
        Order o = [SELECT Id FROM Order LIMIT 1];
        DelayNoticeService.Draft d = DelayNoticeService.draft(o.Id, null);
        System.assertEquals('ai', d.aiSource);
        System.assertEquals('본문', d.body);
    }

    @IsTest
    static void testDraft_aiException_fallback() {
        DelayNoticeInvoker.mockExceptionMessage = 'LLM down';
        Order o = [SELECT Id FROM Order LIMIT 1];

        DelayNoticeService.Draft d = DelayNoticeService.draft(o.Id, null);
        System.assertEquals('fallback', d.aiSource);
        System.assert(d.subject.contains('PO-TEST-1'));
        System.assert(d.body.contains('지연테스트'));
        System.assert(d.body.contains('한도정밀'));
        System.assertNotEquals(null, d.aiError);
    }

    @IsTest
    static void testDraft_aiBlankFields_fallback() {
        DelayNoticeInvoker.mockJsonResponse = '{"subject":"","body":""}';
        Order o = [SELECT Id FROM Order LIMIT 1];
        DelayNoticeService.Draft d = DelayNoticeService.draft(o.Id, null);
        System.assertEquals('fallback', d.aiSource);
    }

    @IsTest
    static void testDraft_invalidJson_fallback() {
        DelayNoticeInvoker.mockJsonResponse = 'broken {';
        Order o = [SELECT Id FROM Order LIMIT 1];
        DelayNoticeService.Draft d = DelayNoticeService.draft(o.Id, null);
        System.assertEquals('fallback', d.aiSource);
    }

    @IsTest
    static void testDraft_nullThrows() {
        try {
            DelayNoticeService.draft(null, null);
            System.assert(false, 'should throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
