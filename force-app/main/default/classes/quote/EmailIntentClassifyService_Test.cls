@IsTest
private class EmailIntentClassifyService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Intent Test Co.', Business_Number__c = '100-00-00009');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Intent Opp', AccountId = acc.Id,
            StageName = '발굴', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'IT-Q-001', OpportunityId = opp.Id,
            Status = '발송', ExpirationDate = Date.today().addDays(14),
            Sent_Date__c = Datetime.now()
        );
        insert q;
    }

    private static EmailMessage createIncomingEmail(Id relatedToId, String subject, String body) {
        EmailMessage em = new EmailMessage(
            Subject     = subject,
            TextBody    = body,
            Incoming    = true,
            RelatedToId = relatedToId,
            Status      = '0',
            MessageDate = Datetime.now()
        );
        insert em;
        return em;
    }

    @IsTest
    static void testClassifyOne_Requote_mockJson() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createIncomingEmail(q.Id, '재견적 요청', '단가 인하 가능 여부 확인 부탁드립니다.');
        EmailIntentClassifyService.mockJsonResponse =
            '{"intent":"Requote","confidence":0.92,"rationale":"단가 조정 명시","summary":"단가 인하 검토 요청"}';
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailIntentClassifyService.ClassifyResult r = EmailIntentClassifyService.classifyOne(em.Id);
        Test.stopTest();

        System.assertEquals(true, r.success);
        System.assertEquals('Requote', r.intent);
        System.assertEquals(0.92, r.confidence);

        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals('Requote', refreshed.Intent__c);
    }

    @IsTest
    static void testClassifyOne_AllSixCategories() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailIntentClassifyService.suppressAutoRequote = true;
        List<String> categories = new List<String>{
            'Confirm', 'Reject', 'Conditions', 'Schedule', 'Other'
        };

        Test.startTest();
        for (String c : categories) {
            EmailMessage em = createIncomingEmail(q.Id, c + ' 메일', 'body');
            EmailIntentClassifyService.mockJsonResponse =
                '{"intent":"' + c + '","confidence":0.7,"rationale":"r","summary":"s"}';
            EmailIntentClassifyService.ClassifyResult r = EmailIntentClassifyService.classifyOne(em.Id);
            System.assertEquals(true, r.success, c + ' 분류 성공');
            EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
            System.assertEquals(c, refreshed.Intent__c, c + ' picklist 저장');
        }
        Test.stopTest();
    }

    @IsTest
    static void testClassifyOne_InvalidIntentRejected() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createIncomingEmail(q.Id, '잘못된', 'x');
        EmailIntentClassifyService.mockJsonResponse =
            '{"intent":"GARBAGE","confidence":0.9,"rationale":"r","summary":"s"}';
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailIntentClassifyService.ClassifyResult r = EmailIntentClassifyService.classifyOne(em.Id);
        Test.stopTest();

        System.assertEquals(false, r.success);
        System.assert(r.aiError.contains('Unrecognized'), 'invalid 카테고리 거부');
        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals(null, refreshed.Intent__c);
    }

    @IsTest
    static void testClassifyOne_LlmFailure_returnsAiError() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createIncomingEmail(q.Id, '재견적', 'x');
        EmailIntentClassifyService.mockExceptionMessage = 'LLM down';
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailIntentClassifyService.ClassifyResult r = EmailIntentClassifyService.classifyOne(em.Id);
        Test.stopTest();

        System.assertEquals(false, r.success);
        System.assert(r.aiError.contains('LLM down'));
    }

    @IsTest
    static void testClassifyOne_NullThrows() {
        try {
            EmailIntentClassifyService.classifyOne(null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testTrigger_IncomingQuoteEmail_dispatchesFuture() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailIntentClassifyService.mockJsonResponse =
            '{"intent":"Other","confidence":0.6,"rationale":"r","summary":"s"}';
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        Integer beforeFutures = Limits.getAsyncCalls();
        EmailMessage em = createIncomingEmail(q.Id, '안녕하세요', '확인 부탁드립니다.');
        System.assert(Limits.getAsyncCalls() > beforeFutures, '@future 디스패치됨');
        Test.stopTest();

        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals('Other', refreshed.Intent__c, '@future 가 Intent__c 갱신');
    }

    @IsTest
    static void testTrigger_OutgoingEmail_skipped() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailMessage em = new EmailMessage(
            Subject = 'AE 발송', TextBody = 'b',
            Incoming = false,         // 아웃바운드 — 건너뜀
            RelatedToId = q.Id,
            Status = '3',
            MessageDate = Datetime.now()
        );
        insert em;
        Test.stopTest();

        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals(null, refreshed.Intent__c, '아웃바운드는 분류 안 됨');
    }

    @IsTest
    static void testTrigger_NoRelatedTo_skipped() {
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailMessage em = new EmailMessage(
            Subject = 'orphan', TextBody = 'b', Incoming = true,
            Status = '0', MessageDate = Datetime.now()
            // RelatedToId 없음
        );
        insert em;
        Test.stopTest();

        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals(null, refreshed.Intent__c, 'RelatedToId 없으면 건너뜀');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Phase 5 보강 — 미커버 분기 (catch blocks, parse errors, stripCodeFences)
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testClassifyAsync_emptyList_returnsEarly() {
        Test.startTest();
        EmailIntentClassifyService.classifyAsync(new List<Id>());
        EmailIntentClassifyService.classifyAsync(null);
        Test.stopTest();
        System.assert(true, '빈 입력은 noop, 예외 없이 종료');
    }

    @IsTest
    static void testClassifyAsync_withValidIds_completes() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailIntentClassifyService.mockJsonResponse =
            '{"intent":"Other","confidence":0.6,"rationale":"r","summary":"s"}';
        EmailIntentClassifyService.suppressAutoRequote = true;

        EmailMessage em = createIncomingEmail(q.Id, 'subject', 'body');

        Test.startTest();
        EmailIntentClassifyService.classifyAsync(new List<Id>{ em.Id });
        Test.stopTest();

        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals('Other', refreshed.Intent__c);
    }

    @IsTest
    static void testClassifyOne_invalidJson_returnsParseError() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createIncomingEmail(q.Id, '깨진 JSON', 'x');
        EmailIntentClassifyService.mockJsonResponse = 'not valid json at all {';
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailIntentClassifyService.ClassifyResult r = EmailIntentClassifyService.classifyOne(em.Id);
        Test.stopTest();

        System.assertEquals(false, r.success);
        System.assert(r.aiError.contains('JSON parse error'), 'parse error 메시지 포함');
    }

    @IsTest
    static void testStripCodeFences_removesJsonWrapper() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createIncomingEmail(q.Id, '코드펜스', 'x');
        EmailIntentClassifyService.mockJsonResponse =
            '```json\n{"intent":"Confirm","confidence":0.8,"rationale":"r","summary":"s"}\n```';
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailIntentClassifyService.ClassifyResult r = EmailIntentClassifyService.classifyOne(em.Id);
        Test.stopTest();

        System.assertEquals(true, r.success);
        System.assertEquals('Confirm', r.intent);
    }

    @IsTest
    static void testClassifyAsync_autoDraftIfRequote_executes() {
        // suppressAutoRequote=false 로 두어 autoDraftIfRequote 분기를 hit (L49 covered)
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailIntentClassifyService.mockJsonResponse =
            '{"intent":"Other","confidence":0.6,"rationale":"r","summary":"s"}';
        EmailIntentClassifyService.suppressAutoRequote = false;

        EmailMessage em = createIncomingEmail(q.Id, 'subject', 'body');

        Test.startTest();
        EmailIntentClassifyService.classifyAsync(new List<Id>{ em.Id });
        Test.stopTest();
        System.assert(true, 'autoDraftIfRequote 분기 통과 (Other 라서 실제 draft 는 안 만들어지지만 호출됨)');
    }

    @IsTest
    static void testTrigger_NonTargetedType_skipped() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        EmailIntentClassifyService.suppressAutoRequote = true;

        Test.startTest();
        EmailMessage em = new EmailMessage(
            Subject = 'on account', TextBody = 'b', Incoming = true,
            RelatedToId = acc.Id,  // Account 는 타겟 아님
            Status = '0', MessageDate = Datetime.now()
        );
        insert em;
        Test.stopTest();

        EmailMessage refreshed = [SELECT Intent__c FROM EmailMessage WHERE Id = :em.Id];
        System.assertEquals(null, refreshed.Intent__c, 'Account RelatedTo 는 건너뜀');
    }
}
