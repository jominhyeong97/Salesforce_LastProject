@isTest
private class BC_RecordWriterTest {

    private static Id setupContentDocument() {
        ContentVersion cv = new ContentVersion(
            Title = 'test', PathOnClient = 'test.jpg',
            VersionData = Blob.valueOf('fake')
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @isTest static void insertExtractingCreatesCardWithStatus() {
        BC_RecordWriter w = new BC_RecordWriter();
        Test.startTest();
        BusinessCard__c card = w.insertExtracting();
        Test.stopTest();
        System.assertNotEquals(null, card.Id);
        BusinessCard__c reloaded = [SELECT Status__c FROM BusinessCard__c WHERE Id = :card.Id];
        System.assertEquals('Extracting', reloaded.Status__c);
    }

    @isTest static void linkContentDocumentCreatesLink() {
        BC_RecordWriter w = new BC_RecordWriter();
        BusinessCard__c card = w.insertExtracting();
        Id cdId = setupContentDocument();

        Test.startTest();
        w.linkContentDocument(card.Id, cdId);
        Test.stopTest();

        ContentDocumentLink cdl = [
            SELECT ShareType, Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :card.Id AND ContentDocumentId = :cdId LIMIT 1
        ];
        System.assertEquals('V', cdl.ShareType);
        System.assertEquals('InternalUsers', cdl.Visibility);
    }

    @isTest static void linkContentDocumentToLeadCreatesLink() {
        BC_RecordWriter w = new BC_RecordWriter();
        Lead lead = new Lead(Company = 'Acme', LastName = '홍');
        w.insertLeadAllowingDuplicates(lead);
        Id cdId = setupContentDocument();

        Test.startTest();
        w.linkContentDocumentToLead(lead.Id, cdId);
        Test.stopTest();

        ContentDocumentLink cdl = [
            SELECT ShareType, Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :lead.Id AND ContentDocumentId = :cdId LIMIT 1
        ];
        System.assertEquals('V', cdl.ShareType);
        System.assertEquals('InternalUsers', cdl.Visibility);
    }

    @isTest static void updateMappedPersistsChanges() {
        BC_RecordWriter w = new BC_RecordWriter();
        BusinessCard__c card = w.insertExtracting();
        card.Status__c = 'Mapped';
        card.Company__c = 'X Co';

        Test.startTest();
        w.updateMapped(card);
        Test.stopTest();

        BusinessCard__c reloaded = [SELECT Status__c, Company__c FROM BusinessCard__c WHERE Id = :card.Id];
        System.assertEquals('Mapped', reloaded.Status__c);
        System.assertEquals('X Co', reloaded.Company__c);
    }

    @isTest static void insertLeadAllowingDuplicatesSucceedsEvenOnDuplicate() {
        BC_RecordWriter w = new BC_RecordWriter();
        // 같은 Email로 두 Lead INSERT — 표준 Duplicate Rule이 켜져 있어도 둘 다 성공해야
        Lead l1 = new Lead(Company = 'Acme', LastName = '홍', Email = 'dup@test.com');
        Lead l2 = new Lead(Company = 'Acme', LastName = '김', Email = 'dup@test.com');

        Test.startTest();
        w.insertLeadAllowingDuplicates(l1);
        w.insertLeadAllowingDuplicates(l2);
        Test.stopTest();

        System.assertNotEquals(null, l1.Id);
        System.assertNotEquals(null, l2.Id);
        System.assertNotEquals(l1.Id, l2.Id);
    }

    @isTest static void markFailedSetsStatusAndReason() {
        BC_RecordWriter w = new BC_RecordWriter();
        BusinessCard__c card = w.insertExtracting();

        Test.startTest();
        w.markFailed(card, 'LLM_FAILURE', 'mock down', 1234);
        Test.stopTest();

        BusinessCard__c reloaded = [SELECT Status__c, Failure_Reason__c, Processing_Duration_Ms__c
                                    FROM BusinessCard__c WHERE Id = :card.Id];
        System.assertEquals('Failed', reloaded.Status__c);
        System.assert(reloaded.Failure_Reason__c.contains('LLM_FAILURE'));
        System.assert(reloaded.Failure_Reason__c.contains('mock down'));
        System.assertEquals(1234, reloaded.Processing_Duration_Ms__c);
    }

    @isTest static void markLeadCreatedSetsLeadLookupAndStatus() {
        BC_RecordWriter w = new BC_RecordWriter();
        BusinessCard__c card = w.insertExtracting();
        Lead lead = new Lead(Company = 'Acme', LastName = '홍');
        w.insertLeadAllowingDuplicates(lead);

        Test.startTest();
        w.markLeadCreated(card, lead.Id, 9999);
        Test.stopTest();

        BusinessCard__c reloaded = [SELECT Status__c, Lead__c, Processing_Duration_Ms__c
                                    FROM BusinessCard__c WHERE Id = :card.Id];
        System.assertEquals('LeadCreated', reloaded.Status__c);
        System.assertEquals(lead.Id, reloaded.Lead__c);
        System.assertEquals(9999, reloaded.Processing_Duration_Ms__c);
    }
}
