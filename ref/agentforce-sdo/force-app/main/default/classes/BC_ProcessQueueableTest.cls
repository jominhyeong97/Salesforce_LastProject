/**
 * BC_ProcessQueueableTest — Queueable이 AutoLeadByBC_Service.processInBackground로 위임하는지 검증.
 */
@isTest
private class BC_ProcessQueueableTest {

    private class StubChecker extends BC_DuplicateChecker {
        public override List<Id> findMatchedIds(Lead lead) { return new List<Id>(); }
    }

    @isTest static void executeRunsBackgroundProcessing() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq = AutoLeadByBC_Service.enqueueProcessing(
            'test.jpg', EncodingUtil.base64Encode(Blob.valueOf('fake')));
        Id cdId = [SELECT ContentDocumentId FROM ContentDocumentLink
                   WHERE LinkedEntityId = :enq.businessCardId LIMIT 1].ContentDocumentId;

        BC_LLMResponse r = new BC_LLMResponse();
        r.isBusinessCard = true;
        r.rawText = 'TC | 이름';
        r.languageDetected = 'ko';
        r.fields.put('company',   new BC_LLMResponse.FieldValue('TC',    1.0));
        r.fields.put('last_name', new BC_LLMResponse.FieldValue('이름',  1.0));
        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.responseToReturn = r;
        AutoLeadByBC_Service.invoker = mock;
        AutoLeadByBC_Service.checker = new StubChecker();

        Test.startTest();
        System.enqueueJob(new BC_ProcessQueueable(enq.businessCardId, cdId));
        Test.stopTest();

        BusinessCard__c card = [SELECT Status__c, Lead__c FROM BusinessCard__c WHERE Id = :enq.businessCardId];
        System.assertEquals('LeadCreated', card.Status__c);
        System.assertNotEquals(null, card.Lead__c);
        System.assertEquals(1, mock.imageCallCount);
    }
}
