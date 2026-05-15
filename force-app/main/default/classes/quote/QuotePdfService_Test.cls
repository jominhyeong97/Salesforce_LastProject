@IsTest
private class QuotePdfService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'PDF Test Co.', Business_Number__c = '100-00-00009');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'PDF Opp', AccountId = acc.Id,
            StageName = '발굴', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Product2 p = new Product2(Name = 'Test Product', ProductCode = 'TP-1', IsActive = true);
        insert p;

        Id stdPb = Test.getStandardPricebookId();
        insert new PricebookEntry(Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 10000, IsActive = true);

        Quote q = new Quote(
            Name = 'PDF-Q-001', OpportunityId = opp.Id, Pricebook2Id = stdPb,
            Status = '초안', ExpirationDate = Date.today().addDays(14)
        );
        insert q;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :p.Id LIMIT 1];
        insert new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = p.Id,
            Quantity = 50, UnitPrice = 10000, Discount_Amount__c = 5000
        );
    }

    @IsTest
    static void testGeneratePdf() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        Id cdId = QuotePdfService.generatePdf(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, cdId, 'ContentDocumentId 반환');
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE ContentDocumentId = :cdId AND LinkedEntityId = :q.Id
        ];
        System.assertEquals(1, links.size(), 'Quote에 PDF 첨부됨');
    }

    @IsTest
    static void testGetLatestPdfIdNullAndExisting() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        // 처음엔 없음
        System.assertEquals(null, QuotePdfService.getLatestPdfId(q.Id));
        // 생성 후엔 있음
        Test.startTest();
        Id cdId = QuotePdfService.generatePdf(q.Id);
        Test.stopTest();
        System.assertEquals(cdId, QuotePdfService.getLatestPdfId(q.Id));
        System.assertEquals(null, QuotePdfService.getLatestPdfId(null));
    }

    @IsTest
    static void testGeneratePdfReplacesOld() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];

        Test.startTest();
        Id firstCdId = QuotePdfService.generatePdf(q.Id);
        Id secondCdId = QuotePdfService.generatePdf(q.Id);
        Test.stopTest();

        System.assertNotEquals(firstCdId, secondCdId, '새 ContentDocument 생성');
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :q.Id
                AND ContentDocument.Title LIKE :(([SELECT Name FROM Quote WHERE Id = :q.Id].Name + '_견적서%'))
        ];
        System.assertEquals(1, links.size(), '옛 PDF 삭제·최신 1개만 남음');
        System.assertEquals(secondCdId, links[0].ContentDocumentId, '두 번째 PDF가 남음');
    }

    @IsTest
    static void testGeneratePdfNullThrows() {
        try {
            QuotePdfService.generatePdf(null);
            System.assert(false, 'should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testToKoreanAmount() {
        System.assertEquals('일금 영원정',           QuotePdfController.toKoreanAmount(0));
        System.assertEquals('일금 영원정',           QuotePdfController.toKoreanAmount(null));
        System.assertEquals('일금 일백사십팔만원정', QuotePdfController.toKoreanAmount(1480000));
        System.assertEquals('일금 일십만원정',       QuotePdfController.toKoreanAmount(100000));
        System.assertEquals('일금 일억이천삼백사십오만육천칠백팔십구원정', QuotePdfController.toKoreanAmount(123456789));
    }
}
