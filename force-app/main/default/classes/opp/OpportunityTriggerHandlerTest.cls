@isTest
private class OpportunityTriggerHandlerTest {

    private static Account makeAccount(String name, String bn) {
        Account a = new Account(Name = name);
        if (String.isNotBlank(bn)) a.Business_Number__c = bn;
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId, String stage, String descValue) {
        Opportunity o = new Opportunity(
            Name = 'TestOpp', AccountId = accountId, StageName = stage,
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
        insert new OpportunityContactRole(OpportunityId = oppId, ContactId = c.Id, IsPrimary = true);
    }

    @isTest
    static void testStageTransitionBlockedWhenGateFails() {
        Account a = makeAccount('NoBn', null);
        Opportunity o = makeOpp(a.Id, '발굴', 'spec');
        addContactRole(o.Id, a.Id);

        Test.startTest();
        Boolean failed = false;
        try {
            o.StageName = '견적 작성';
            update o;
        } catch (DmlException e) {
            failed = true;
            System.assert(e.getMessage().contains('사업자번호'), '에러 메시지: ' + e.getMessage());
        }
        Test.stopTest();
        System.assertEquals(true, failed, '게이트 미충족 시 update 실패해야');
    }

    @isTest
    static void testStageTransitionAllowedWhenGatePasses() {
        Account a = makeAccount('OkCo', '100-00-00009');
        Opportunity o = makeOpp(a.Id, '발굴', '{"partName":"베어링"}');
        addContactRole(o.Id, a.Id);

        Test.startTest();
        o.StageName = '견적 작성';
        update o;
        Test.stopTest();

        Opportunity reload = [SELECT StageName FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('견적 작성', reload.StageName);
    }

    @isTest
    static void testNonStageChangeNotBlocked() {
        Account a = makeAccount('NoBn', null);
        Opportunity o = makeOpp(a.Id, '발굴', 'spec');

        Test.startTest();
        o.Name = 'RenamedOpp'; // Stage 변경 X
        update o;
        Test.stopTest();
        // Exception 없이 통과해야
    }

    @isTest
    static void testUnmappedTransitionPasses() {
        // 매핑되지 않은 전환(예: 협상 → 수주)은 게이트 없음 — 통과
        Account a = makeAccount('AnyCo', null);
        Opportunity o = makeOpp(a.Id, '협상', null);

        Test.startTest();
        o.StageName = '수주';
        update o;
        Test.stopTest();

        Opportunity reload = [SELECT StageName FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('수주', reload.StageName);
    }

    @isTest
    static void testNullArgsSafe() {
        OpportunityTriggerHandler.handleBeforeInsert(null);
        OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>());
        OpportunityTriggerHandler.handleBeforeUpdate(null, null);
        OpportunityTriggerHandler.handleBeforeUpdate(new List<Opportunity>(), new Map<Id, Opportunity>());
        OpportunityTriggerHandler.handleAfterUpdate(null, null);
        OpportunityTriggerHandler.handleAfterUpdate(new List<Opportunity>(), new Map<Id, Opportunity>());
    }

    // ─────────────────────────────────────────────────────────────────────
    // BEFORE INSERT — Pricebook 자동 할당
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testBeforeInsert_setsStandardPricebookWhenNull() {
        Account a = makeAccount('PB Auto', null);
        Opportunity o = new Opportunity(
            Name='Auto PB', AccountId=a.Id, StageName='발굴',
            CloseDate=Date.today().addDays(30)
            // Pricebook2Id 의도적으로 미설정
        );

        Test.startTest();
        insert o;
        Test.stopTest();

        Opportunity result = [SELECT Pricebook2Id FROM Opportunity WHERE Id = :o.Id];
        System.assertNotEquals(null, result.Pricebook2Id,
            'before insert 에서 Pricebook 자동 할당돼야');
        System.assertEquals(Test.getStandardPricebookId(), result.Pricebook2Id,
            'Standard Pricebook 이어야');
    }

    @isTest
    static void testBeforeInsert_preservesExplicitPricebook() {
        Account a = makeAccount('Explicit PB', null);
        Id stdPb = Test.getStandardPricebookId();
        Opportunity o = new Opportunity(
            Name='Explicit', AccountId=a.Id, StageName='발굴',
            CloseDate=Date.today().addDays(30), Pricebook2Id=stdPb
        );

        Test.startTest();
        insert o;
        Test.stopTest();

        Opportunity result = [SELECT Pricebook2Id FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(stdPb, result.Pricebook2Id,
            '명시 지정된 Pricebook 은 유지돼야');
    }

    // ─────────────────────────────────────────────────────────────────────
    // Day 9 #1 — Won_To_Order (handleAfterUpdate)
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testWonTransition_createsOrderAndCopiesLines() {
        Account a = makeAccount('Won Co.', '100-00-00009');
        Id stdPb = Test.getStandardPricebookId();

        Product2 p = new Product2(Name='Bearing-W', ProductCode='BR-W', IsActive=true);
        insert p;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id=stdPb, Product2Id=p.Id, UnitPrice=1000, IsActive=true
        );
        insert pbe;

        Date promised = Date.today().addDays(60);
        Opportunity o = new Opportunity(
            Name='Won Opp', AccountId=a.Id, StageName='협상',
            CloseDate=Date.today().addDays(30), Pricebook2Id=stdPb,
            Promised_Delivery_Date__c=promised // D38: Order.EndDate 로 승계 검증
        );
        insert o;

        Quote q = new Quote(
            Name='Q-Won', OpportunityId=o.Id, Pricebook2Id=stdPb, Status='수락'
        );
        insert q;
        insert new QuoteLineItem(
            QuoteId=q.Id, PricebookEntryId=pbe.Id, Quantity=7, UnitPrice=1500
        );

        Test.startTest();
        o.StageName = '수주';
        update o;
        Test.stopTest();

        List<Order> orders = [
            SELECT Id, Opportunity__c, PoNumber, Status, Production_Status__c, EndDate,
                   (SELECT Id, Quantity, UnitPrice FROM OrderItems)
            FROM Order WHERE Opportunity__c = :o.Id
        ];
        System.assertEquals(1, orders.size(), 'Won → Order 1건 자동');
        System.assert(orders[0].PoNumber.startsWith('PO-' + Date.today().year() + '-W'),
            'PoNumber prefix. actual=' + orders[0].PoNumber);
        System.assertEquals('Pending', orders[0].Production_Status__c);
        System.assertEquals(promised, orders[0].EndDate,
            'D38: Opp.Promised_Delivery_Date__c → Order.EndDate 승계');

        System.assertEquals(1, orders[0].OrderItems.size(), 'Quote 라인 1건 → OrderItem 1건 (Case A)');
        System.assertEquals(7, orders[0].OrderItems[0].Quantity);
        System.assertEquals(1500, orders[0].OrderItems[0].UnitPrice);
    }

    @isTest
    static void testWonTransition_noPricebook_skipsOrder() {
        Account a = makeAccount('NoPbCo', '100-00-00009');
        Opportunity o = new Opportunity(
            Name='No PB Opp', AccountId=a.Id, StageName='협상',
            CloseDate=Date.today().addDays(30)
            // Pricebook2Id 미설정 — before insert 트리거가 채움
        );
        insert o;
        // before-insert 자동 할당을 우회해 'Pricebook 없는 Opp' 상태 강제 (safety guard 검증용)
        o.Pricebook2Id = null;
        update o;

        Test.startTest();
        o.StageName = '수주';
        update o;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Order WHERE Opportunity__c = :o.Id],
            'Pricebook 없으면 Order 미생성 (handleAfterUpdate 안전 가드)');
    }

    @isTest
    static void testWonTransition_alreadyHasOrder_idempotent() {
        Account a = makeAccount('IdempCo', '100-00-00009');
        Id stdPb = Test.getStandardPricebookId();

        Opportunity o = new Opportunity(
            Name='Idemp Opp', AccountId=a.Id, StageName='협상',
            CloseDate=Date.today().addDays(30), Pricebook2Id=stdPb
        );
        insert o;

        // 이미 Order 1개 존재
        insert new Order(
            AccountId=a.Id, Opportunity__c=o.Id, EffectiveDate=Date.today(),
            Status='Draft', Pricebook2Id=stdPb, PoNumber='PO-PRE-0001'
        );

        Test.startTest();
        o.StageName = '수주';
        update o;
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Order WHERE Opportunity__c = :o.Id],
            '기존 Order 있으면 신규 미생성 (idempotent)');
    }

    @isTest
    static void testNonWonTransition_doesNotCreateOrder() {
        Account a = makeAccount('NonWonCo', '100-00-00009');
        Id stdPb = Test.getStandardPricebookId();
        Opportunity o = new Opportunity(
            Name='NonWon Opp', AccountId=a.Id, StageName='발굴',
            CloseDate=Date.today().addDays(30), Pricebook2Id=stdPb,
            Promised_Delivery_Date__c=Date.today().addDays(45), // D38: 발굴→견적 작성 게이트 통과
            Description='{"partName":"x"}'
        );
        insert o;
        addContactRole(o.Id, a.Id);

        Test.startTest();
        o.StageName = '견적 작성';
        update o;
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Order WHERE Opportunity__c = :o.Id],
            '수주 아닌 전환은 Order 생성 안 함');
    }
}
