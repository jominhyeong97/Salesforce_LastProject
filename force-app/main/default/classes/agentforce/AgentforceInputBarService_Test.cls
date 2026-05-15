@IsTest
private class AgentforceInputBarService_Test {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = '입력바테스트', Business_Number__c = '100-00-00009');
        insert a;
        Opportunity o = new Opportunity(
            Name = 'IB Opp', AccountId = a.Id,
            StageName = '발굴', CloseDate = Date.today().addDays(30)
        );
        insert o;
        Quote q = new Quote(
            Name = 'IB-Q-001', OpportunityId = o.Id,
            Status = '발송', Sent_Date__c = Datetime.now().addDays(-5),
            ExpirationDate = Date.today().addDays(14)
        );
        insert q;
    }

    @IsTest
    static void testAsk_emptyUtterance_returnsNoop() {
        AgentforceInputBarService.AgentResponse r = AgentforceInputBarService.ask('', null);
        System.assertEquals('noop', r.action);
        System.assert(r.message.contains('질문'));
    }

    // ─── ReAct router 통과 케이스 ────────────────────────────────────────

    @IsTest
    static void testReact_routerSelectsToday_synthesizesNaturalText() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetTodayPriorityList","args":{},"rationale":"오늘 우선순위 요청"}';
        AgentSynthesizeInvoker.mockResponse =
            '오늘 우선순위는 총 7건이에요. 위험 Order 부터 살펴보세요.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('오늘 뭐 해야 해?', null);

        System.assertEquals('GetTodayPriorityListAction', r.action);
        System.assert(r.message.contains('오늘 우선순위'),
            'synthesized message expected, got: ' + r.message);
    }

    @IsTest
    static void testReact_routerSelectsAccountSummary_byName() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetAccountSummary","args":{"accountName":"입력바테스트"},"rationale":"고객사 요약"}';
        AgentSynthesizeInvoker.mockResponse =
            '입력바테스트는 진행중 Opp 1건이 있어요.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('입력바테스트 물건 나갔나요?', null);

        System.assertEquals('GetAccountSummaryAction', r.action);
        System.assert(r.message.contains('입력바테스트'));
    }

    @IsTest
    static void testReact_routerSelectsAccountSummary_argMissing_usesContext() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetAccountSummary","args":{},"rationale":"고객사 요약"}';
        AgentSynthesizeInvoker.mockResponse = '입력바테스트 요약 응답입니다.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('미수금 어때?', a.Id);

        System.assertEquals('GetAccountSummaryAction', r.action);
        System.assertNotEquals(null, r.message);
    }

    @IsTest
    static void testReact_routerSelectsAccountSummary_argMissingNoContext_returnsMissingArg() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetAccountSummary","args":{},"rationale":"고객사 요약"}';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('미수금 어때?', null);
        System.assertEquals('missing_args', r.action);
        System.assert(r.message.contains('고객사'));
    }

    @IsTest
    static void testReact_routerSelectsCrossSell_withContext() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetCrossSellCandidates","args":{},"rationale":"추천"}';
        AgentSynthesizeInvoker.mockResponse = '추천 부품 응답입니다.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('뭐 더 팔 수 있을까?', a.Id);
        System.assertEquals('GetCrossSellCandidatesAction', r.action);
    }

    @IsTest
    static void testReact_routerSelectsCrossSell_missingArg_returnsMissingArg() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetCrossSellCandidates","args":{},"rationale":"추천"}';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('뭐 더 팔 수 있을까?', null);
        System.assertEquals('missing_args', r.action);
    }

    @IsTest
    static void testReact_routerSelectsOrderRisk() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetOrderAtRisk","args":{},"rationale":"납기 위험"}';
        AgentSynthesizeInvoker.mockResponse = '납기 위험 응답입니다.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('주문 어때?', null);
        System.assertEquals('GetOrderAtRiskAction', r.action);
        System.assert(r.message.contains('납기'));
    }

    @IsTest
    static void testReact_routerSelectsDraftFollowup_withQuoteContext() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        AgentRouterInvoker.mockResponse =
            '{"tool":"DraftFollowupEmail","args":{},"rationale":"follow-up"}';
        AgentSynthesizeInvoker.mockResponse = 'follow-up 메일 안내드려요.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('회신 부탁 메일 써줘', q.Id);
        System.assertEquals('DraftFollowupEmailAction', r.action);
        System.assertNotEquals(null, r.urgency);
    }

    @IsTest
    static void testReact_routerSelectsDraftFollowup_noQuoteContext_returnsMissingArg() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"DraftFollowupEmail","args":{},"rationale":"follow-up"}';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('회신 메일 써줘', null);
        System.assertEquals('missing_args', r.action);
    }

    // ─── PaymentCheck (Day 15 신규) ──────────────────────────────────────

    @IsTest
    static void testReact_routerSelectsPaymentCheck_today() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"PaymentCheck","args":{"mode":"today"},"rationale":"오늘 회수"}';
        AgentSynthesizeInvoker.mockResponse = '오늘 입금 내역 안내드려요.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('오늘 입금 들어온 거 있어?', null);
        System.assertEquals('PaymentCheckAction', r.action);
        System.assert(r.message.contains('입금'));
    }

    @IsTest
    static void testReact_routerSelectsPaymentCheck_account_byName() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"PaymentCheck","args":{"mode":"account","accountName":"입력바테스트"},"rationale":"고객사 잔액"}';
        AgentSynthesizeInvoker.mockResponse = '입력바테스트 잔액 안내드려요.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('입력바테스트 잔액 얼마야?', null);
        System.assertEquals('PaymentCheckAction', r.action);
    }

    @IsTest
    static void testReact_routerSelectsPaymentCheck_account_argMissing_usesContext() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        AgentRouterInvoker.mockResponse =
            '{"tool":"PaymentCheck","args":{"mode":"account"},"rationale":"잔액"}';
        AgentSynthesizeInvoker.mockResponse = '잔액 응답입니다.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('잔액 얼마?', a.Id);
        System.assertEquals('PaymentCheckAction', r.action);
    }

    @IsTest
    static void testReact_routerSelectsPaymentCheck_atrisk() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"PaymentCheck","args":{"mode":"atrisk"},"rationale":"미수금 상위"}';
        AgentSynthesizeInvoker.mockResponse = '미수금 상위 안내드려요.';

        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('미수금 큰 데 어디?', null);
        System.assertEquals('PaymentCheckAction', r.action);
    }

    // ─── router none / 실패 → AgentInputFallback / 최종 fallback ────────

    @IsTest
    static void testReact_routerToolNone_fallsThroughToLlmFallback() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"none","args":{},"rationale":"잡담"}';
        AgentInputFallbackInvoker.mockResponse = '안녕하세요! 무엇을 도와드릴까요?';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('안녕하세요', null);
        System.assertEquals('llm_fallback', r.action);
    }

    @IsTest
    static void testReact_routerToolNone_fallbackEmpty_finalFallback() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"none","args":{},"rationale":"잡담"}';
        AgentInputFallbackInvoker.mockResponse = '';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('완전 모르는 질문', null);
        System.assertEquals('fallback', r.action);
        System.assert(r.message.contains('우선순위'));
    }

    @IsTest
    static void testReact_routerDown_fallsThroughToLlmFallback() {
        AgentRouterInvoker.mockExceptionMessage = 'router down';
        AgentInputFallbackInvoker.mockResponse = '도우미 응답';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('아무 질문', null);
        System.assertEquals('llm_fallback', r.action);
    }

    @IsTest
    static void testReact_allLlmFail_finalFallback() {
        AgentRouterInvoker.mockExceptionMessage = 'router down';
        AgentInputFallbackInvoker.mockExceptionMessage = 'fallback down';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('완전 모르는 질문', null);
        System.assertEquals('fallback', r.action);
    }

    @IsTest
    static void testReact_routerReturnsInvalidJson_fallsThroughToLlmFallback() {
        AgentRouterInvoker.mockResponse = 'not a json at all';
        AgentInputFallbackInvoker.mockResponse = '도움말 응답';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('아무 질문', null);
        System.assertEquals('llm_fallback', r.action);
    }

    @IsTest
    static void testReact_routerReturnsUnknownTool_fallsThroughToLlmFallback() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"BogusTool","args":{},"rationale":"???"}';
        AgentInputFallbackInvoker.mockResponse = '도움말 응답';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('아무 질문', null);
        System.assertEquals('llm_fallback', r.action);
    }

    @IsTest
    static void testReact_routerReturnsCodeFencedJson_stripsAndParses() {
        AgentRouterInvoker.mockResponse =
            '```json\n{"tool":"GetOrderAtRisk","args":{},"rationale":"위험"}\n```';
        AgentSynthesizeInvoker.mockResponse = '납기 응답입니다.';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('주문 위험?', null);
        System.assertEquals('GetOrderAtRiskAction', r.action);
    }

    @IsTest
    static void testReact_synthesizeFails_returnsRawSummary() {
        AgentRouterInvoker.mockResponse =
            '{"tool":"GetTodayPriorityList","args":{},"rationale":"오늘"}';
        AgentSynthesizeInvoker.mockExceptionMessage = 'synthesize down';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('오늘 뭐 해야 해?', null);
        System.assertEquals('GetTodayPriorityListAction', r.action);
        System.assert(r.message.contains('오늘 우선순위') || r.message.contains('정상'),
            'raw summary expected, got: ' + r.message);
    }

    @IsTest
    static void testReact_contextHint_buildsForQuote() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        AgentRouterInvoker.mockResponse =
            '{"tool":"DraftFollowupEmail","args":{},"rationale":"follow-up"}';
        AgentSynthesizeInvoker.mockResponse = '응답';
        AgentforceInputBarService.AgentResponse r =
            AgentforceInputBarService.ask('이 견적 follow-up', q.Id);
        System.assertEquals('DraftFollowupEmailAction', r.action);
    }

    // ─── Invoker 단위 테스트 (Test.isRunningTest mock 경로 커버) ────────

    @IsTest
    static void testInvokers_mockResponse_returnsString() {
        AgentRouterInvoker.mockResponse = '{"tool":"none"}';
        System.assertEquals('{"tool":"none"}', AgentRouterInvoker.invoke('hi', ''));

        AgentSynthesizeInvoker.mockResponse = '응답';
        System.assertEquals('응답', AgentSynthesizeInvoker.invoke('hi', 'GetOrderAtRisk', '{}'));
    }

    @IsTest
    static void testInvokers_mockException_throws() {
        AgentRouterInvoker.mockExceptionMessage = 'down';
        try {
            AgentRouterInvoker.invoke('hi', '');
            System.assert(false, 'expected exception');
        } catch (AgentRouterInvoker.AgentRouterException e) {
            System.assert(e.getMessage().contains('down'));
        }

        AgentSynthesizeInvoker.mockExceptionMessage = 'down';
        try {
            AgentSynthesizeInvoker.invoke('hi', 'tool', '{}');
            System.assert(false, 'expected exception');
        } catch (AgentSynthesizeInvoker.AgentSynthesizeException e) {
            System.assert(e.getMessage().contains('down'));
        }
    }
}
