@IsTest
private class QuoteRequoteService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Requote Test Co.', Business_Number__c = '100-00-00009');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Requote Opp', AccountId = acc.Id,
            StageName = '견적 발송', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Product2 p = new Product2(Name = 'Bearing 6201', ProductCode = 'BR-6201', IsActive = true);
        insert p;
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = p.Id, UnitPrice = 10000, IsActive = true);
        insert pbe;

        Quote q = new Quote(
            Name = 'RQ-Q-001',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPbId,
            Status = '발송',
            ExpirationDate = Date.today().addDays(14),
            Sent_Date__c = Datetime.now()
        );
        insert q;

        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = p.Id,
            Quantity = 100, UnitPrice = 10000, Discount_Amount__c = 0
        );
    }

    private static EmailMessage createRequoteEmail(Id relatedToId) {
        EmailMessage em = new EmailMessage(
            Subject = '재견적 요청', TextBody = '단가 5% 조정 가능?',
            Incoming = true, RelatedToId = relatedToId,
            Intent__c = 'Requote',
            Status = '0', MessageDate = Datetime.now()
        );
        insert em;
        return em;
    }

    @IsTest
    static void testDraftFromEmail_clonesQuote_withAiSummary() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createRequoteEmail(q.Id);

        QuoteRequoteService.mockJsonResponse =
            '{"summary":"단가 5% 인하 요구. 발주 의사 강함.","confidence":0.85,"expirationDays":10,' +
            '"lineAdjustments":[{"productCode":"BR-6201","changeType":"discount","suggestedValue":0.05,"rationale":"단가 5% 인하"}]}';

        Test.startTest();
        QuoteRequoteService.DraftResult r = QuoteRequoteService.draftFromEmail(em.Id);
        Test.stopTest();

        System.assertEquals(true, r.success);
        System.assertEquals('ai', r.aiSource);
        System.assertNotEquals(null, r.draftQuoteId);
        System.assertEquals(1, r.lineCount);
        System.assertEquals(0.85, r.aiConfidence);

        Quote draft = [
            SELECT Id, Name, Status, ExpirationDate, AI_Draft_Confidence__c, Description,
                   AE_Edit_Count__c, OpportunityId
            FROM Quote WHERE Id = :r.draftQuoteId
        ];
        System.assertEquals('초안', draft.Status);
        System.assert(draft.Name.contains('재견적'), '이름에 (재견적) 접미사');
        System.assertEquals(Date.today().addDays(10), draft.ExpirationDate, 'AI expirationDays=10 반영');
        System.assertEquals(0.85, draft.AI_Draft_Confidence__c);
        System.assert(draft.Description.contains('AI 재견적 분석'), 'Description에 AI 분석 블록');
        System.assert(draft.Description.contains('BR-6201'), '조정안 ProductCode 포함');
        System.assertEquals(0, draft.AE_Edit_Count__c);

        List<QuoteLineItem> draftLines = [
            SELECT Quantity, UnitPrice FROM QuoteLineItem WHERE QuoteId = :r.draftQuoteId
        ];
        System.assertEquals(1, draftLines.size());
        System.assertEquals(100, draftLines[0].Quantity, '원본 수량 보존 (가격 비변형 정책)');
        System.assertEquals(10000, draftLines[0].UnitPrice);
    }

    @IsTest
    static void testDraftFromEmail_LlmFailure_fallback() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        EmailMessage em = createRequoteEmail(q.Id);
        QuoteRequoteService.mockExceptionMessage = 'Prompt template not found';

        Test.startTest();
        QuoteRequoteService.DraftResult r = QuoteRequoteService.draftFromEmail(em.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, 'fallback 도 draft 생성 성공');
        System.assertEquals('fallback', r.aiSource);
        System.assert(r.aiError.contains('Prompt template not found'));
        Quote draft = [SELECT Description, AI_Draft_Confidence__c FROM Quote WHERE Id = :r.draftQuoteId];
        System.assertEquals(0.0, draft.AI_Draft_Confidence__c);
        System.assert(draft.Description.contains('AE'), 'Fallback 안내 메시지');
    }

    @IsTest
    static void testDraftFromEmail_ResolveQuoteFromOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        EmailMessage em = createRequoteEmail(opp.Id);

        QuoteRequoteService.mockJsonResponse =
            '{"summary":"test","confidence":0.5,"expirationDays":14,"lineAdjustments":[]}';

        Test.startTest();
        QuoteRequoteService.DraftResult r = QuoteRequoteService.draftFromEmail(em.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, 'Opp RelatedTo → 최신 발송 Quote 자동 검색');
        System.assertNotEquals(null, r.draftQuoteId);
    }

    @IsTest
    static void testAutoDraftIfRequote_filtersNonRequote() {
        Quote q = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        EmailMessage emRequote = createRequoteEmail(q.Id);
        EmailMessage emOther = new EmailMessage(
            Subject = '단순 확인', TextBody = 'b', Incoming = true,
            RelatedToId = q.Id, Intent__c = 'Other',
            Status = '0', MessageDate = Datetime.now()
        );
        insert emOther;

        QuoteRequoteService.mockJsonResponse =
            '{"summary":"test","confidence":0.5,"expirationDays":14,"lineAdjustments":[]}';

        Test.startTest();
        QuoteRequoteService.autoDraftIfRequote(new List<Id>{ emRequote.Id, emOther.Id });
        Test.stopTest();

        Integer draftCount = [
            SELECT COUNT() FROM Quote
            WHERE OpportunityId = :q.OpportunityId AND Status = '초안'
        ];
        System.assertEquals(1, draftCount, 'Requote 만 draft 생성, Other 는 무시');
    }

    @IsTest
    static void testDraftFromEmail_NullThrows() {
        try {
            QuoteRequoteService.draftFromEmail(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testDraftFromEmail_NoLinkedQuote_returnsError() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        EmailMessage em = new EmailMessage(
            Subject = 'orphan', TextBody = 'b', Incoming = true,
            RelatedToId = acc.Id,  // Account 는 Quote 매핑 없음
            Intent__c = 'Requote',
            Status = '0', MessageDate = Datetime.now()
        );
        insert em;

        Test.startTest();
        QuoteRequoteService.DraftResult r = QuoteRequoteService.draftFromEmail(em.Id);
        Test.stopTest();

        System.assertEquals(false, r.success);
        System.assert(r.aiError.contains('Quote'));
    }
}
