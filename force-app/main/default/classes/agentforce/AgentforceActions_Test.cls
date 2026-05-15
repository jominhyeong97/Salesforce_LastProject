/**
 * AgentforceActions_Test — Day 10 Agentforce 4 Action 통합 테스트.
 *
 * 커버리지 — GetTodayPriorityListAction / GetOrderAtRiskAction
 *           / GetAccountSummaryAction / DraftFollowupEmailAction
 *
 * @group Agentforce
 */
@IsTest
private class AgentforceActions_Test {

    // ─────────────────────────────────────────────────────────────────────
    // 공통 fixture
    // ─────────────────────────────────────────────────────────────────────

    private static Account makeAccount(String name) {
        Account a = new Account(
            Name                     = name,
            Business_Number__c       = '100-00-00009',
            CEO_Name__c              = '홍길동',
            Credit_Limit__c          = 100000000,
            External_Credit_Score__c = 720,
            Total_AR__c              = 25000000,
            Long_Term_Debtor__c      = true
        );
        insert a;
        return a;
    }

    private static Order makeOrder(Id accountId, Integer riskScore, String prodStatus) {
        Order o = new Order(
            AccountId               = accountId,
            EffectiveDate           = Date.today(),
            Status                  = 'Draft',
            Production_Status__c    = prodStatus,
            Delivery_Risk_Score__c  = riskScore,
            PoNumber                = 'PO-TEST-' + Math.mod(System.currentTimeMillis(), 99999)
        );
        insert o;
        return o;
    }

    // ─────────────────────────────────────────────────────────────────────
    // GetTodayPriorityListAction
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetTodayPriorityList_emptyOrg_returnsZeros() {
        Test.startTest();
        List<GetTodayPriorityListAction.Response> outs =
            GetTodayPriorityListAction.run(new List<GetTodayPriorityListAction.Request>{
                new GetTodayPriorityListAction.Request()
            });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        GetTodayPriorityListAction.Response r = outs[0];
        System.assertNotEquals(null, r.summary);
        System.assertNotEquals(null, r.detailsJson);
        System.assertEquals(0, r.newRfqCount + r.priorityLeadCount + r.sentQuoteCount
                              + r.riskyOrderCount + r.arActionCount,
                            'fresh test org should have 0 cockpit items');
    }

    @IsTest
    static void testGetTodayPriorityList_withRiskyOrder_includesInSummary() {
        Account a = makeAccount('테스트 위험사 ' + System.currentTimeMillis());
        makeOrder(a.Id, 88, 'InProgress');

        Test.startTest();
        List<GetTodayPriorityListAction.Response> outs =
            GetTodayPriorityListAction.run(new List<GetTodayPriorityListAction.Request>{ new GetTodayPriorityListAction.Request() });
        Test.stopTest();

        System.assert(outs[0].riskyOrderCount >= 1, 'should detect risky order');
        System.assert(outs[0].summary.contains('위험'), 'summary should mention 위험');
    }

    // ─────────────────────────────────────────────────────────────────────
    // GetOrderAtRiskAction
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetOrderAtRisk_defaultThreshold_filters() {
        Account a = makeAccount('위험사 ' + System.currentTimeMillis());
        makeOrder(a.Id, 90, 'InProgress'); // 대형지연
        makeOrder(a.Id, 75, 'InProgress'); // 위험
        makeOrder(a.Id, 30, 'InProgress'); // 정상 — 70 미만이라 제외

        Test.startTest();
        List<GetOrderAtRiskAction.Response> outs =
            GetOrderAtRiskAction.run(new List<GetOrderAtRiskAction.Request>{
                new GetOrderAtRiskAction.Request()
            });
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(2, outs[0].riskCount, 'only orders with score >= 70 should match');
        System.assert(outs[0].summary.contains('대형지연'), 'summary should call out 대형지연');
    }

    @IsTest
    static void testGetOrderAtRisk_customThreshold_respected() {
        Account a = makeAccount('임계테스트사 ' + System.currentTimeMillis());
        makeOrder(a.Id, 50, 'InProgress');
        makeOrder(a.Id, 60, 'InProgress');

        GetOrderAtRiskAction.Request req = new GetOrderAtRiskAction.Request();
        req.minRiskScore = 50;
        req.maxResults   = 5;

        Test.startTest();
        List<GetOrderAtRiskAction.Response> outs =
            GetOrderAtRiskAction.run(new List<GetOrderAtRiskAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(2, outs[0].riskCount, 'lower threshold should include both orders');
    }

    @IsTest
    static void testGetOrderAtRisk_noMatch_emptySummary() {
        Test.startTest();
        List<GetOrderAtRiskAction.Response> outs =
            GetOrderAtRiskAction.run(new List<GetOrderAtRiskAction.Request>{
                new GetOrderAtRiskAction.Request()
            });
        Test.stopTest();

        System.assertEquals(0, outs[0].riskCount);
        System.assert(outs[0].summary.contains('없음'), 'should indicate no risky orders');
    }

    // ─────────────────────────────────────────────────────────────────────
    // GetAccountSummaryAction
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetAccountSummary_byId_returnsFullSummary() {
        Account a = makeAccount('일치 Account ' + System.currentTimeMillis());

        GetAccountSummaryAction.Request req = new GetAccountSummaryAction.Request();
        req.accountId = a.Id;

        Test.startTest();
        List<GetAccountSummaryAction.Response> outs =
            GetAccountSummaryAction.run(new List<GetAccountSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, outs[0].found);
        System.assertEquals(a.Id, outs[0].accountId);
        System.assertEquals('100-00-00009', outs[0].businessNumber);
        System.assertEquals('홍길동', outs[0].ceoName);
        System.assertEquals(true, outs[0].longTermDebtor);
        System.assert(outs[0].summary.contains('장기미수'), 'summary should flag 장기미수');
    }

    @IsTest
    static void testGetAccountSummary_byName_partialMatch() {
        Account a = makeAccount('한도정밀공업 ' + System.currentTimeMillis());

        GetAccountSummaryAction.Request req = new GetAccountSummaryAction.Request();
        req.accountName = '한도정밀공업';

        Test.startTest();
        List<GetAccountSummaryAction.Response> outs =
            GetAccountSummaryAction.run(new List<GetAccountSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, outs[0].found);
        System.assertEquals(a.Id, outs[0].accountId);
    }

    @IsTest
    static void testGetAccountSummary_notFound_returnsFoundFalse() {
        GetAccountSummaryAction.Request req = new GetAccountSummaryAction.Request();
        req.accountName = '존재하지않는회사' + System.currentTimeMillis();

        Test.startTest();
        List<GetAccountSummaryAction.Response> outs =
            GetAccountSummaryAction.run(new List<GetAccountSummaryAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, outs[0].found);
        System.assert(outs[0].summary.contains('찾지 못'), 'summary should indicate not found');
    }

    @IsTest
    static void testGetAccountSummary_emptyRequest_returnsFoundFalse() {
        Test.startTest();
        List<GetAccountSummaryAction.Response> outs =
            GetAccountSummaryAction.run(new List<GetAccountSummaryAction.Request>{
                new GetAccountSummaryAction.Request()
            });
        Test.stopTest();

        System.assertEquals(false, outs[0].found);
    }

    // ─────────────────────────────────────────────────────────────────────
    // DraftFollowupEmailAction
    // ─────────────────────────────────────────────────────────────────────

    private static Quote makeQuote() {
        Account a = makeAccount('견적테스트사 ' + System.currentTimeMillis());
        Contact c = new Contact(LastName = '김담당', AccountId = a.Id);
        insert c;
        Opportunity opp = new Opportunity(
            Name      = '테스트 거래',
            StageName = '견적 작성',
            CloseDate = Date.today().addDays(30),
            AccountId = a.Id
        );
        insert opp;

        Pricebook2 standard = new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
        update standard;
        Quote q = new Quote(
            Name           = 'Q-FOLLOWUP-TEST',
            OpportunityId  = opp.Id,
            ContactId      = c.Id,
            Status         = '발송',
            Pricebook2Id   = Test.getStandardPricebookId()
        );
        insert q;
        return q;
    }

    @IsTest
    static void testDraftFollowupEmail_aiPath_parsesSubjectAndBody() {
        Quote q = makeQuote();
        DraftFollowupEmailAction.mockAiResponse =
            '{"subject":"[테스트] Q-001 회신 부탁","body":"안녕하세요.\\n회신 부탁드립니다.\\n\\n한도정밀 영업팀"}';

        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('ai', outs[0].aiSource);
        System.assertEquals('[테스트] Q-001 회신 부탁', outs[0].emailSubject);
        System.assert(outs[0].emailBody.contains('한도정밀'));
    }

    @IsTest
    static void testDraftFollowupEmail_codeFencesStripped() {
        Quote q = makeQuote();
        DraftFollowupEmailAction.mockAiResponse =
            '```json\n{"subject":"펜스 테스트","body":"본문\\n서명"}\n```';

        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('ai', outs[0].aiSource, 'D26 stripCodeFences should handle fenced JSON');
        System.assertEquals('펜스 테스트', outs[0].emailSubject);
    }

    @IsTest
    static void testDraftFollowupEmail_aiFails_fallbackEngages() {
        Quote q = makeQuote();
        DraftFollowupEmailAction.mockExceptionMessage = 'LLM unreachable';

        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;
        req.additionalContext = '단가 5% 인하 검토 가능';

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('fallback', outs[0].aiSource);
        System.assertEquals('LLM unreachable', outs[0].aiError);
        System.assert(outs[0].emailSubject.contains('회신'), 'fallback subject should ask for reply');
        System.assert(outs[0].emailBody.contains('단가 5% 인하'), 'fallback body should include AE context');
        System.assert(outs[0].emailBody.contains('한도정밀 영업팀'), 'fallback should sign as 한도정밀 영업팀');
    }

    @IsTest
    static void testDraftFollowupEmail_missingQuoteId_softFallback() {
        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('fallback', outs[0].aiSource);
        System.assert(outs[0].aiError.contains('quoteId'), 'should indicate missing quoteId');
        System.assertNotEquals(null, outs[0].emailSubject);
        System.assertNotEquals(null, outs[0].emailBody);
    }

    @IsTest
    static void testDraftFollowupEmail_malformedJson_fallback() {
        Quote q = makeQuote();
        DraftFollowupEmailAction.mockAiResponse = 'not a json at all';

        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('fallback', outs[0].aiSource);
    }

    @IsTest
    static void testDraftFollowupEmail_quoteWithoutContact_fallbackUsesGenericGreeting() {
        Account a = makeAccount('Contact없는사 ' + System.currentTimeMillis());
        Opportunity opp = new Opportunity(
            Name      = 'No-contact 거래',
            StageName = '견적 작성',
            CloseDate = Date.today().addDays(30),
            AccountId = a.Id
        );
        insert opp;
        Pricebook2 standard = new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);
        update standard;
        Quote q = new Quote(
            Name           = 'Q-NOCONTACT',
            OpportunityId  = opp.Id,
            Status         = '발송',
            Pricebook2Id   = Test.getStandardPricebookId()
        );
        insert q;

        DraftFollowupEmailAction.mockExceptionMessage = 'LLM disabled for test';
        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('fallback', outs[0].aiSource);
        System.assert(outs[0].emailBody.startsWith('담당자님,'), 'no contact → generic 담당자님 greeting');
    }

    @IsTest
    static void testDraftFollowupEmail_oldQuote_urgentTone() {
        Quote q = makeQuote();
        q.Sent_Date__c = DateTime.now().addDays(-10);
        update q;

        DraftFollowupEmailAction.mockExceptionMessage = 'force fallback';
        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('urgent', outs[0].urgency, '10일 경과 견적은 urgent');
        System.assert(outs[0].daysSinceSent >= 10, '10일 이상 표시');
        System.assert(outs[0].emailSubject.startsWith('[재요청]'), 'urgent subject prefix');
        System.assert(outs[0].emailBody.contains('1주일이 경과'), 'urgent body line');
    }

    @IsTest
    static void testDraftFollowupEmail_freshQuote_standardTone() {
        Quote q = makeQuote();
        q.Sent_Date__c = DateTime.now().addDays(-1);
        update q;

        DraftFollowupEmailAction.mockExceptionMessage = 'force fallback';
        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('standard', outs[0].urgency, '1일 경과는 standard');
        System.assertEquals(1, outs[0].daysSinceSent);
    }

    @IsTest
    static void testDraftFollowupEmail_missingSubject_treatsAsParseFailure() {
        Quote q = makeQuote();
        DraftFollowupEmailAction.mockAiResponse = '{"subject":"","body":""}';

        DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
        req.quoteId = q.Id;

        Test.startTest();
        List<DraftFollowupEmailAction.Response> outs =
            DraftFollowupEmailAction.run(new List<DraftFollowupEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals('fallback', outs[0].aiSource, 'blank subject/body should trigger fallback');
        System.assert(outs[0].aiError.contains('subject') || outs[0].aiError.contains('body'));
    }
}
