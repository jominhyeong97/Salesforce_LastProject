@isTest
private class StageGateServiceTest {

    private static Account makeAccount(String name, String bn) {
        Account a = new Account(Name = name);
        if (String.isNotBlank(bn)) a.Business_Number__c = bn;
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId, String stage, String descValue) {
        Opportunity o = new Opportunity(
            Name = 'TestOpp',
            AccountId = accountId,
            StageName = stage,
            CloseDate = Date.today().addDays(30),
            Promised_Delivery_Date__c = Date.today().addDays(45), // D38: 게이트 default 통과
            Description = descValue
        );
        insert o;
        return o;
    }

    private static void addContactRole(Id oppId, Id accId) {
        Contact c = new Contact(LastName = 'Kim', AccountId = accId);
        insert c;
        OpportunityContactRole r = new OpportunityContactRole(
            OpportunityId = oppId, ContactId = c.Id, IsPrimary = true
        );
        insert r;
    }

    @isTest
    static void testGateAllSatisfied() {
        Account a = makeAccount('한라정공', '100-00-00009'); // valid checksum
        Opportunity o = makeOpp(a.Id, '발굴', '{"partName":"베어링","quantity":100}');

        Test.startTest();
        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);
        Test.stopTest();

        System.assertEquals(true, r.passed, '사업자번호 + 납기일 OK 면 게이트 통과');
        System.assertEquals('발굴', r.currentStage);
        System.assertEquals('견적 작성', r.nextStage);
        System.assertEquals(2, r.rules.size(), 'D38: 사업자번호 + 약속 납기일 2 룰');
        Map<String, Boolean> sat = new Map<String, Boolean>();
        for (StageGateService.GateRule g : r.rules) sat.put(g.label, g.satisfied);
        System.assertEquals(true, sat.get('사업자번호 등록'));
        System.assertEquals(true, sat.get('약속 납기일 등록'));
    }

    @isTest
    static void testGate_missingDeliveryDate_fails() {
        // D38: 사업자번호 OK + 납기일 없음 → 게이트 fail (납기일만)
        Account a = makeAccount('NoDeliveryCo', '100-00-00009');
        Opportunity o = new Opportunity(
            Name = 'NoDelivery', AccountId = a.Id, StageName = '발굴',
            CloseDate = Date.today().addDays(30)
            // Promised_Delivery_Date__c 명시 null
        );
        insert o;

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        System.assertEquals(false, r.passed, '납기일 미입력 → 게이트 차단');
        Map<String, Boolean> sat = new Map<String, Boolean>();
        Map<String, String> hintMap = new Map<String, String>();
        for (StageGateService.GateRule g : r.rules) {
            sat.put(g.label, g.satisfied);
            hintMap.put(g.label, g.hintText);
        }
        System.assertEquals(true, sat.get('사업자번호 등록'), '사업자번호는 OK');
        System.assertEquals(false, sat.get('약속 납기일 등록'), '납기일은 fail');
        System.assertEquals('납기일을 저장해주세요', hintMap.get('약속 납기일 등록'),
            '게이트 메시지 한국어 정합');
    }

    @isTest
    static void testGateMissingBusinessNumber() {
        Account a = makeAccount('NoBnCo', null);
        Opportunity o = makeOpp(a.Id, '발굴', 'spec');

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        System.assertEquals(false, r.passed);
        System.assertEquals('사업자번호 등록', r.rules[0].label);
        System.assertEquals(false, r.rules[0].satisfied);
    }

    @isTest
    static void testEvaluateFailuresReturnsOnlyMissing() {
        Account a = makeAccount('PartialCo', null); // 사업자번호 없음
        Opportunity o = makeOpp(a.Id, '발굴', 'spec');

        Opportunity reload = [
            SELECT Id, StageName, Description, Promised_Delivery_Date__c,
                   AccountId, Account.Business_Number__c,
                   (SELECT Id FROM OpportunityContactRoles)
            FROM Opportunity WHERE Id = :o.Id
        ];

        List<StageGateService.GateRule> fails = StageGateService.evaluateFailures(reload, '발굴', '견적 작성');
        System.assertEquals(1, fails.size(), '사업자번호 1건만 미충족 (납기일은 makeOpp default 로 통과)');
        System.assertEquals('사업자번호 등록', fails[0].label);
    }

    @isTest
    static void testNotMappedTransitionAlwaysPasses() {
        Account a = makeAccount('AnyCo', null);
        Opportunity o = makeOpp(a.Id, '협상', 'spec'); // 매핑되지 않은 stage

        Opportunity reload = [
            SELECT Id, StageName, Description, Promised_Delivery_Date__c,
                   AccountId, Account.Business_Number__c,
                   (SELECT Id FROM OpportunityContactRoles)
            FROM Opportunity WHERE Id = :o.Id
        ];
        List<StageGateService.GateRule> fails = StageGateService.evaluateFailures(reload, '협상', '수주');
        System.assertEquals(0, fails.size(), '매핑되지 않은 전환은 게이트 없음');
    }

    @isTest
    static void testNullSafe() {
        System.assertEquals(null, StageGateService.checkOppGate(null));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rule 2: 견적 작성 → 견적 발송 (Quote 존재 + 라인)
    // ─────────────────────────────────────────────────────────────────────

    /** Quote 페이지에 첨부 1건 link — 신규 첨부 룰 통과용. */
    private static void attachToQuote(Id quoteId) {
        ContentVersion cv = new ContentVersion(
            Title = 'TestQuoteAtt', PathOnClient = 'att.pdf',
            VersionData = Blob.valueOf('dummy pdf'), IsMajorVersion = true
        );
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = quoteId, ContentDocumentId = cdId, ShareType = 'V'
        );
    }

    @isTest
    static void testRule2_quoteBuilding_passesWithLines() {
        Account a = makeAccount('Rule2 Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 작성', 'spec');

        Product2 p = new Product2(Name = 'TP', IsActive = true);
        insert p;
        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 1000, IsActive = true
        );
        insert pbe;

        Quote q = new Quote(
            Name = 'R2-Q-1', OpportunityId = o.Id, Pricebook2Id = stdPb,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 1000
        );
        attachToQuote(q.Id);

        Test.startTest();
        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);
        Test.stopTest();

        System.assertEquals('견적 작성', r.currentStage);
        System.assertEquals('견적 발송', r.nextStage);
        System.assertEquals(3, r.rules.size(), '견적 존재 + 라인 + 첨부 3 룰');
        for (StageGateService.GateRule g : r.rules) {
            System.assertEquals(true, g.satisfied, g.label + ' should be satisfied');
        }
        System.assertEquals(true, r.passed);
    }

    @isTest
    static void testRule2_quoteBuilding_failsWithoutQuote() {
        Account a = makeAccount('Rule2NoQuote Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 작성', 'spec');

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        System.assertEquals(false, r.passed);
        System.assertEquals(3, r.rules.size());
        for (StageGateService.GateRule g : r.rules) {
            System.assertEquals(false, g.satisfied);
        }
    }

    @isTest
    static void testRule2_quoteBuilding_failsWithoutLines() {
        Account a = makeAccount('Rule2NoLines Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 작성', 'spec');
        Id stdPb = Test.getStandardPricebookId();
        Quote q = new Quote(
            Name = 'R2-Q-NL', OpportunityId = o.Id, Pricebook2Id = stdPb,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        System.assertEquals(false, r.passed);
        // quoteExists=true but hasLineItems=false, hasAttachment=false
        Map<String, Boolean> sat = new Map<String, Boolean>();
        for (StageGateService.GateRule g : r.rules) sat.put(g.label, g.satisfied);
        System.assertEquals(true, sat.get('견적 존재'));
        System.assertEquals(false, sat.get('견적 라인'));
        System.assertEquals(false, sat.get('견적 첨부 파일'));
    }

    @isTest
    static void testRule2_quoteBuilding_failsWithoutAttachment() {
        Account a = makeAccount('Rule2NoAtt Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 작성', 'spec');

        Product2 p = new Product2(Name = 'TP NoAtt', IsActive = true);
        insert p;
        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 1000, IsActive = true
        );
        insert pbe;

        Quote q = new Quote(
            Name = 'R2-Q-NA', OpportunityId = o.Id, Pricebook2Id = stdPb,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 1000
        );

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        Map<String, Boolean> sat = new Map<String, Boolean>();
        for (StageGateService.GateRule g : r.rules) sat.put(g.label, g.satisfied);
        System.assertEquals(true, sat.get('견적 존재'));
        System.assertEquals(true, sat.get('견적 라인'));
        System.assertEquals(false, sat.get('견적 첨부 파일'),
            '첨부 없으면 satisfied=false');
        System.assertEquals(false, r.passed);
    }

    @isTest
    static void testRule2_quoteBuilding_withAttachment_passes() {
        Account a = makeAccount('Rule2Att Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 작성', 'spec');

        Product2 p = new Product2(Name = 'TP Att', IsActive = true);
        insert p;
        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 1000, IsActive = true
        );
        insert pbe;

        Quote q = new Quote(
            Name = 'R2-Q-Att', OpportunityId = o.Id, Pricebook2Id = stdPb,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 1000
        );
        attachToQuote(q.Id);

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        Map<String, Boolean> sat = new Map<String, Boolean>();
        for (StageGateService.GateRule g : r.rules) sat.put(g.label, g.satisfied);
        System.assertEquals(true, sat.get('견적 첨부 파일'),
            '첨부 1건 시 satisfied=true');
        System.assertEquals(true, r.passed);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rule 3: 견적 발송 → 협상 (Quote.Status='수락' 필수)
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testRule3_quoteAccepted_passes() {
        Account a = makeAccount('Rule3Acc Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 발송', 'spec');

        Quote q = new Quote(
            Name = 'R3-Q-ACC', OpportunityId = o.Id,
            Status = '수락', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        Test.startTest();
        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);
        Test.stopTest();

        System.assertEquals('견적 발송', r.currentStage);
        System.assertEquals('협상', r.nextStage);
        System.assertEquals(1, r.rules.size());
        System.assertEquals('고객 수락', r.rules[0].label);
        System.assertEquals(true, r.rules[0].satisfied);
        System.assertEquals(true, r.passed);
    }

    @isTest
    static void testRule3_quoteSentButNotAccepted_fails() {
        // Status='발송' 이지만 아직 수락 전 — 협상 단계로 진행 금지.
        Account a = makeAccount('Rule3Sent Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 발송', 'spec');

        Quote q = new Quote(
            Name = 'R3-Q-SENT', OpportunityId = o.Id,
            Status = '발송', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        System.assertEquals(false, r.passed, '수락 전엔 미통과');
        System.assertEquals('고객 수락', r.rules[0].label);
        System.assertEquals(false, r.rules[0].satisfied);
    }

    @isTest
    static void testRule3_quoteDraft_fails() {
        Account a = makeAccount('Rule3Draft Co.', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '견적 발송', 'spec');

        Quote q = new Quote(
            Name = 'R3-Q-DR', OpportunityId = o.Id,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);

        System.assertEquals(false, r.passed);
        System.assertEquals(false, r.rules[0].satisfied);
    }

    @isTest
    static void testTerminalStages_noNextStage() {
        Account a = makeAccount('TerminalCo', '100-00-00009');
        Opportunity won = makeOpp(a.Id, '수주', 'spec');

        StageGateService.GateResult r = StageGateService.checkOppGate(won.Id);
        // 수주 → 수주 (자기 자신, terminal). 매핑 없음 → 룰 0
        System.assertEquals('수주', r.currentStage);
        System.assertEquals('수주', r.nextStage);
        System.assertEquals(0, r.rules.size());
        System.assertEquals(true, r.passed);
    }
}
