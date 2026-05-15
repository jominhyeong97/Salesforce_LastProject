/**
 * QuotePdfController_Test — Phase 5 커버리지 보강.
 * Visualforce StandardController 생성자 + loadQuote / loadLines / address formatter / Korean amount.
 */
@IsTest
private class QuotePdfController_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'PDF Ctrl Co.',
            Business_Number__c = '100-00-00009',
            CEO_Name__c = '홍길동',
            BillingStreet = '단원로 123',
            BillingCity = '안산시',
            BillingPostalCode = '15577',
            Phone = '031-1234-5678'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'PDF Ctrl Opp', AccountId = acc.Id,
            StageName = '협상', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Product2 p = new Product2(Name = '베어링 6204', ProductCode = 'BR-6204', IsActive = true);
        insert p;
        Id stdPb = Test.getStandardPricebookId();
        insert new PricebookEntry(Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 10000, IsActive = true);

        Quote q = new Quote(
            Name = 'PDF-CTRL-Q-001',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPb,
            Status = '발송',
            ExpirationDate = Date.today().addDays(14),
            Description = '협의된 단가 적용.\n납기 2주.',
            Tax = 0,
            AE_Edit_Count__c = 5
        );
        insert q;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :p.Id LIMIT 1];
        insert new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = p.Id,
                              Quantity = 10, UnitPrice = 10000, Discount_Amount__c = 5000),
            new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = p.Id,
                              Quantity = 5, UnitPrice = 20000, Discount_Amount__c = 0)
        };
    }

    @IsTest
    static void testCtor_fullQuote_loadsAllFields() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        Test.startTest();
        QuotePdfController ctrl = new QuotePdfController(new ApexPages.StandardController(q));
        Test.stopTest();

        // Brand
        System.assertEquals('한 도 정 밀', ctrl.brandCompany);
        System.assertNotEquals(null, ctrl.brandEmail);

        // Account 정보
        System.assertEquals('PDF Ctrl Co.', ctrl.accountName);
        System.assertEquals('100-00-00009', ctrl.accountBizNumber);
        System.assertEquals('홍길동', ctrl.accountCEO);
        System.assert(ctrl.accountAddress.contains('15577'), '우편번호 포함');
        System.assert(ctrl.accountAddress.contains('안산시'), '시 포함');
        System.assert(ctrl.accountAddress.contains('단원로 123'), '도로 포함');

        // Opportunity / Quote 정보
        System.assertEquals('PDF Ctrl Opp', ctrl.opportunityName);
        System.assertEquals('협상', ctrl.opportunityStage);
        System.assertEquals('발송', ctrl.statusLabel);
        System.assertEquals(5, ctrl.aeEditCount);
        System.assertNotEquals(null, ctrl.quoteNumber);

        // Description HTML escape + 줄바꿈
        System.assert(ctrl.hasDescription);
        System.assert(ctrl.descriptionHtml.contains('<br/>'), '줄바꿈 br 변환');

        // 라인 + 합계 — 10*10000 - 5000 + 5*20000 - 0 = 95000 + 100000 = 195000 (gross 200000 disc 5000)
        System.assertEquals(2, ctrl.lines.size());
        System.assertEquals(200000, ctrl.subtotal);
        System.assertEquals(5000, ctrl.totalDiscount);
        System.assertEquals(195000, ctrl.netTotal);
        System.assertEquals(195000, ctrl.grandTotal);
        System.assertEquals('일금 일십구만오천원정', ctrl.netTotalKorean);
        System.assertEquals(false, ctrl.hasNoLines);

        // 라인 행
        QuotePdfController.LineRow first = ctrl.lines[0];
        System.assertEquals(1, first.seq);
        System.assertEquals('베어링 6204', first.productName);
        System.assertEquals(95000, first.lineNetTotal);
    }

    @IsTest
    static void testCtor_noLines_hasNoLinesTrue() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        delete [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id];

        Test.startTest();
        QuotePdfController ctrl = new QuotePdfController(new ApexPages.StandardController(q));
        Test.stopTest();

        System.assertEquals(true, ctrl.hasNoLines);
        System.assertEquals(0, ctrl.subtotal);
        System.assertEquals(0, ctrl.netTotal);
        System.assertEquals('일금 영원정', ctrl.netTotalKorean);
    }

    @IsTest
    static void testCtor_minimalAccount_addressDash() {
        // Account 의 빌링 주소 모두 비움
        Account a = [SELECT Id FROM Account LIMIT 1];
        update new Account(Id = a.Id,
            BillingStreet = null, BillingCity = null, BillingPostalCode = null,
            Phone = null, CEO_Name__c = null
        );
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        QuotePdfController ctrl = new QuotePdfController(new ApexPages.StandardController(q));
        Test.stopTest();

        System.assertEquals('-', ctrl.accountAddress);
        System.assertEquals('-', ctrl.accountCEO);
        System.assertEquals('-', ctrl.accountPhone);
    }

    @IsTest
    static void testToKoreanAmount_boundaryCases() {
        System.assertEquals('일금 영원정', QuotePdfController.toKoreanAmount(null));
        System.assertEquals('일금 영원정', QuotePdfController.toKoreanAmount(0));
        System.assertEquals('일금 영원정', QuotePdfController.toKoreanAmount(-100));
        System.assertEquals('일금 일원정', QuotePdfController.toKoreanAmount(1));
        System.assertEquals('일금 구원정', QuotePdfController.toKoreanAmount(9));
        System.assertEquals('일금 일십원정', QuotePdfController.toKoreanAmount(10));
        System.assertEquals('일금 일백원정', QuotePdfController.toKoreanAmount(100));
        System.assertEquals('일금 일천원정', QuotePdfController.toKoreanAmount(1000));
        System.assertEquals('일금 일만원정', QuotePdfController.toKoreanAmount(10000));
        System.assertEquals('일금 일억원정', QuotePdfController.toKoreanAmount(100000000));
    }
}
