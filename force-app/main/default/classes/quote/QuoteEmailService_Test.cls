@IsTest
private class QuoteEmailService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Email Test Co.', Business_Number__c = '100-00-00009');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Email Opp', AccountId = acc.Id,
            StageName = '발굴', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'EM-Q-001', OpportunityId = opp.Id,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        ContentVersion cv = new ContentVersion(
            Title = 'EM-Q-001_견적서',
            PathOnClient = 'EM-Q-001.pdf',
            VersionData = Blob.valueOf('mock pdf'),
            ContentLocation = 'S'
        );
        insert cv;

        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = cdId, LinkedEntityId = q.Id,
            ShareType = 'V', Visibility = 'AllUsers'
        );
    }

    @IsTest
    static void testGetDefaultEmail() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        QuoteEmailService.EmailDefaultDTO dto = QuoteEmailService.getDefaultEmail(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO 반환');
        System.assert(dto.subject.contains('견적서'), '제목에 "견적서" 포함');
        System.assert(dto.body.contains('한도정밀'), '본문에 "한도정밀" 포함');
    }

    @IsTest
    static void testGetDefaultEmailNullThrows() {
        try {
            QuoteEmailService.getDefaultEmail(null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testSendQuoteCustom() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Id cdId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        Id sent = QuoteEmailService.sendQuote(
            q.Id, 'test@example.com', cdId,
            '커스텀 제목 — 시연용', '안녕하세요\n사용자가 직접 작성한 본문입니다.'
        );
        Test.stopTest();

        System.assertEquals(q.Id, sent);
        Quote refreshed = [SELECT Status, Sent_Date__c FROM Quote WHERE Id = :q.Id];
        System.assertEquals('발송', refreshed.Status);
        System.assertNotEquals(null, refreshed.Sent_Date__c);
    }

    @IsTest
    static void testSendQuoteFallbackDefaults() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Id cdId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        QuoteEmailService.sendQuote(q.Id, 'test@example.com', cdId, null, null);
        Test.stopTest();

        Quote refreshed = [SELECT Status FROM Quote WHERE Id = :q.Id];
        System.assertEquals('발송', refreshed.Status);
    }

    @IsTest
    static void testAutoLinkAndWrap_replacesPlainUrlsWithTrackedAnchors() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        String body = '견적 확인: https://example.com/quote/123 입니다.<br/>약관: http://example.com/terms';

        Test.startTest();
        String wrapped = QuoteEmailService.autoLinkAndWrap(body, q.Id, 'https://site.example.com');
        Test.stopTest();

        System.assert(wrapped.contains('<a href="https://site.example.com/' + q.Id +
            '/click?url=https://example.com/quote/123">https://example.com/quote/123</a>'),
            'https URL 이 click endpoint wrapper 로 변환되어야 함');
        System.assert(wrapped.contains('<a href="https://site.example.com/' + q.Id +
            '/click?url=http://example.com/terms">http://example.com/terms</a>'),
            'http URL 도 변환되어야 함');
    }

    @IsTest
    static void testAutoLinkAndWrap_emptyBody_passesThrough() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        System.assertEquals('', QuoteEmailService.autoLinkAndWrap('', q.Id, 'https://x'));
        System.assertEquals(null, QuoteEmailService.autoLinkAndWrap(null, q.Id, 'https://x'));
    }

    @IsTest
    static void testTrackingBaseUrl_blankLabel_returnsNull() {
        // 기본 라벨 값은 공백 — 데모 직전 사용자가 채워 넣음. test 환경은 null 이어야 send 가 픽셀 미주입.
        Test.startTest();
        String url = QuoteEmailService.trackingBaseUrl();
        Test.stopTest();
        System.assertEquals(null, url, 'Custom Label 미설정 시 null');
    }

    // ─────────────────────────────────────────────────────────────────────
    // FR-OPP-002 — Quote 발송 시 Opportunity Stage 자동 전이
    // ─────────────────────────────────────────────────────────────────────

    @IsTest
    static void testSendQuote_autoTransitions_QuoteBuildingToSent() {
        Quote q = [SELECT Id, OpportunityId FROM Quote LIMIT 1];

        // Opp 를 '견적 작성' 으로 옮기고 (StageGate Rule 1 Business_Number 통과)
        update new Opportunity(Id = q.OpportunityId, StageName = '견적 작성');

        // QuoteLineItem 1 건 추가 (StageGate '견적 작성→견적 발송' hasLineItems 통과)
        Product2 p = new Product2(Name = 'AUTO-TEST', IsActive = true);
        insert p;
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId, Product2Id = p.Id, UnitPrice = 1000, IsActive = true
        );
        insert pbe;
        update new Quote(Id = q.Id, Pricebook2Id = stdPbId);
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 1000
        );

        Id cdId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        QuoteEmailService.sendQuote(q.Id, 'test@example.com', cdId, '제목', '본문');
        Test.stopTest();

        Opportunity refreshed = [SELECT StageName FROM Opportunity WHERE Id = :q.OpportunityId];
        System.assertEquals('견적 발송', refreshed.StageName,
            'Quote 발송 시 Opp Stage 가 견적 작성 → 견적 발송 으로 자동 전이되어야 함');
    }

    @IsTest
    static void testSendQuote_skipsTransition_WhenStageIsDiscovery() {
        Quote q = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        // Opp 가 '발굴' 단계면 자동 전이 skip (TestSetup 기본값이 '발굴' 이므로 update 불필요)
        Id cdId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        QuoteEmailService.sendQuote(q.Id, 'test@example.com', cdId, '제목', '본문');
        Test.stopTest();

        Opportunity refreshed = [SELECT StageName FROM Opportunity WHERE Id = :q.OpportunityId];
        System.assertEquals('발굴', refreshed.StageName,
            '발굴 단계는 자동 전이 대상 아님');
    }

    @IsTest
    static void testSendQuoteValidations() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Id cdId = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id LIMIT 1].ContentDocumentId;

        Integer caught = 0;
        try { QuoteEmailService.sendQuote(null, 'a@b.com', cdId, 'S', 'B'); } catch (AuraHandledException e) { caught++; }
        try { QuoteEmailService.sendQuote(q.Id, '', cdId, 'S', 'B'); } catch (AuraHandledException e) { caught++; }
        try { QuoteEmailService.sendQuote(q.Id, 'a@b.com', null, 'S', 'B'); } catch (AuraHandledException e) { caught++; }
        System.assertEquals(3, caught, '3 validation 모두 throw');
    }
}
