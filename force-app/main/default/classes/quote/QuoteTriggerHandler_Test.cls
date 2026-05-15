@IsTest
private class QuoteTriggerHandler_Test {

    private static Account makeAccount(String name) {
        Account a = new Account(
            Name = name,
            Business_Number__c = '100-00-00009',
            Phone = '02-1234-5678'
        );
        insert a;
        // BillingAddress 는 State/Country picklist 제약으로 test 에서 skip — 핸들러 의 BillingName/ContactId/Phone 만 검증
        return a;
    }

    private static Contact makeContact(Id accId) {
        Contact c = new Contact(
            FirstName = '민형', LastName = '조', AccountId = accId,
            Email = 'test@example.com', Phone = '010-9999-0000'
        );
        insert c;
        return c;
    }

    private static Opportunity makeOpp(Id accId, String stage) {
        Opportunity o = new Opportunity(
            Name = 'QT Opp', AccountId = accId,
            StageName = stage, CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert o;
        return o;
    }

    private static PricebookEntry makePbe(String name, Decimal price) {
        Product2 p = new Product2(Name = name, IsActive = true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = p.Id, UnitPrice = price, IsActive = true
        );
        insert pbe;
        return pbe;
    }

    // ─── Rule 1 — 주소·Contact 복사 ───

    @IsTest
    static void testBeforeInsert_copiesAddressAndContact() {
        Account a = makeAccount('주소복사 Co.');
        Contact c = makeContact(a.Id);
        Opportunity o = makeOpp(a.Id, '견적 작성');

        Test.startTest();
        Quote q = new Quote(
            Name = 'Q-AddrCopy', OpportunityId = o.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        Test.stopTest();

        Quote reload = [SELECT BillingName, ShippingName,
                               ContactId, Email, Phone
                        FROM Quote WHERE Id = :q.Id];
        System.assertEquals('주소복사 Co.', reload.BillingName, 'Account.Name → BillingName');
        System.assertEquals('주소복사 Co.', reload.ShippingName, 'Account.Name → ShippingName');
        System.assertEquals(c.Id, reload.ContactId, '1차 Contact → ContactId');
        System.assertEquals('test@example.com', reload.Email);
        System.assertEquals('010-9999-0000', reload.Phone);
    }

    @IsTest
    static void testBeforeInsert_noContact_usesAccountPhone() {
        Account a = makeAccount('NoContact Co.');
        Opportunity o = makeOpp(a.Id, '견적 작성');

        Quote q = new Quote(
            Name = 'Q-NoContact', OpportunityId = o.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        Quote reload = [SELECT ContactId, Phone FROM Quote WHERE Id = :q.Id];
        System.assertEquals(null, reload.ContactId);
        System.assertEquals('02-1234-5678', reload.Phone, 'Account.Phone fallback');
    }

    @IsTest
    static void testBeforeInsert_existingValuesNotOverwritten() {
        Account a = makeAccount('Existing Co.');
        makeContact(a.Id);
        Opportunity o = makeOpp(a.Id, '견적 작성');

        Quote q = new Quote(
            Name = 'Q-Existing', OpportunityId = o.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = '초안', ExpirationDate = Date.today().addDays(14),
            BillingName = '직접 입력 이름',
            Email = 'custom@example.com'
        );
        insert q;

        Quote reload = [SELECT BillingName, Email FROM Quote WHERE Id = :q.Id];
        System.assertEquals('직접 입력 이름', reload.BillingName, '기존 BillingName 보존');
        System.assertEquals('custom@example.com', reload.Email, '기존 Email 보존');
    }

    @IsTest
    static void testBeforeInsert_emptyOrNull_noFailure() {
        Test.startTest();
        QuoteTriggerHandler.handleBeforeInsert(new List<Quote>());
        QuoteTriggerHandler.handleBeforeInsert(null);
        Test.stopTest();
        System.assert(true);
    }

    // ─── Rule 2 — Status '수락' 시 OpportunityLineItem 동기화 ───

    @IsTest
    static void testAfterUpdate_acceptedStatus_copiesLinesToOpp() {
        Account a = makeAccount('Accept Co.');
        makeContact(a.Id);
        Opportunity o = makeOpp(a.Id, '견적 발송');
        PricebookEntry pbe = makePbe('TP-1', 1000);

        Quote q = new Quote(
            Name = 'Q-Accept', OpportunityId = o.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = '발송', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Quantity = 5, UnitPrice = 1000, Discount = 0
        );

        Integer oliBefore = [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :o.Id];
        System.assertEquals(0, oliBefore, '초기 OppLineItem 없음');

        // Status '발송' → '수락' 전이
        Test.startTest();
        q.Status = '수락';
        update q;
        Test.stopTest();

        List<OpportunityLineItem> oli = [
            SELECT Id, Quantity, UnitPrice FROM OpportunityLineItem
            WHERE OpportunityId = :o.Id
        ];
        System.assertEquals(1, oli.size(), '수락 전이 시 1 OpportunityLineItem 자동 생성');
        System.assertEquals(5, oli[0].Quantity);
        System.assertEquals(1000, oli[0].UnitPrice);
    }

    @IsTest
    static void testAfterUpdate_acceptedStatus_replacesExistingOli() {
        Account a = makeAccount('Replace Co.');
        makeContact(a.Id);
        Opportunity o = makeOpp(a.Id, '견적 발송');
        PricebookEntry pbe = makePbe('TP-R', 2000);

        // 기존 OppLineItem 1건
        insert new OpportunityLineItem(
            OpportunityId = o.Id, PricebookEntryId = pbe.Id,
            Quantity = 99, UnitPrice = 99
        );

        Quote q = new Quote(
            Name = 'Q-Replace', OpportunityId = o.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = '발송', ExpirationDate = Date.today().addDays(14)
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Quantity = 3, UnitPrice = 2000
        );

        q.Status = '수락';
        update q;

        List<OpportunityLineItem> oli = [
            SELECT Quantity FROM OpportunityLineItem WHERE OpportunityId = :o.Id
        ];
        System.assertEquals(1, oli.size(), '기존 OLI 1건 제거 + 새 1건 생성');
        System.assertEquals(3, oli[0].Quantity, '새 QuoteLineItem Quantity 반영');
    }

    @IsTest
    static void testAfterUpdate_nonAcceptedStatus_noChange() {
        Account a = makeAccount('NoAccept Co.');
        makeContact(a.Id);
        Opportunity o = makeOpp(a.Id, '견적 작성');

        Quote q = new Quote(
            Name = 'Q-NoAccept', OpportunityId = o.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        q.Status = '발송';
        update q;

        Integer oliCount = [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :o.Id];
        System.assertEquals(0, oliCount, '수락 아니면 OLI 변화 없음');
    }

    @IsTest
    static void testAfterUpdate_emptyOrNull_noFailure() {
        Test.startTest();
        QuoteTriggerHandler.handleAfterUpdate(new List<Quote>(), new Map<Id, Quote>());
        QuoteTriggerHandler.handleAfterUpdate(null, null);
        Test.stopTest();
        System.assert(true);
    }
}
