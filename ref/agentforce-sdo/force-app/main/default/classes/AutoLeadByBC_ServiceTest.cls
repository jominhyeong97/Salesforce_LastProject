/**
 * AutoLeadByBC_ServiceTest — 비동기 흐름 단위 테스트.
 *   - enqueueProcessing: 동기 단계 (ContentVersion + BusinessCard + Link + Queueable enqueue)
 *   - processInBackground: 비동기 본 처리 (LLM, 매핑, Lead 생성, Status 갱신)
 *   - fetchResult: LWC가 Status 변화 후 결과 회수
 */
@isTest
private class AutoLeadByBC_ServiceTest {

    private class StubChecker extends BC_DuplicateChecker {
        public List<Id> stubMatchedIds = new List<Id>();
        public override List<Id> findMatchedIds(Lead lead) { return stubMatchedIds; }
    }

    private static String fakeBase64() {
        return EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'));
    }

    private static BC_LLMResponse buildHappyResponse() {
        BC_LLMResponse r = new BC_LLMResponse();
        r.isBusinessCard = true;
        r.rawText = 'TestCo | Hong Gildong | hong@test.com';
        r.languageDetected = 'ko';
        r.fields.put('company', new BC_LLMResponse.FieldValue('TestCo', 1.0));
        r.fields.put('last_name', new BC_LLMResponse.FieldValue('홍길동', 1.0));
        r.fields.put('title', new BC_LLMResponse.FieldValue('대표이사', 1.0));
        r.fields.put('email', new BC_LLMResponse.FieldValue('hong@test.com', 1.0));
        r.fields.put('mobile_phone', new BC_LLMResponse.FieldValue('010-1234-5678', 1.0));
        r.fields.put('website', new BC_LLMResponse.FieldValue('', 0));
        return r;
    }

    private static Id linkedContentDocumentId(Id cardId) {
        return [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :cardId LIMIT 1
        ].ContentDocumentId;
    }

    @isTest static void enqueueProcessingCreatesQueuedCardAndLink() {
        AutoLeadByBC_Service.skipQueueable = true;

        Test.startTest();
        AutoLeadByBC_Service.ResultDTO dto =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Test.stopTest();

        System.assertEquals('Queued', dto.status);
        System.assertNotEquals(null, dto.businessCardId);

        BusinessCard__c card = [SELECT Status__c FROM BusinessCard__c WHERE Id = :dto.businessCardId];
        System.assertEquals('Queued', card.Status__c);

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :dto.businessCardId];
        System.assertEquals(1, linkCount, '명함에 이미지 ContentDocumentLink 1건 기대');
    }

    @isTest static void enqueueProcessingNullInputFails() {
        Test.startTest();
        AutoLeadByBC_Service.ResultDTO dto = AutoLeadByBC_Service.enqueueProcessing(null, null);
        Test.stopTest();
        System.assertEquals('Failed', dto.status);
        System.assertEquals('INVALID_INPUT', dto.failureCode);
    }

    @isTest static void processInBackgroundHappyPathCreatesLeadAndLinks() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Id cdId = linkedContentDocumentId(enq.businessCardId);

        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.responseToReturn = buildHappyResponse();
        AutoLeadByBC_Service.invoker = mock;
        AutoLeadByBC_Service.checker = new StubChecker();

        Test.startTest();
        AutoLeadByBC_Service.processInBackground(enq.businessCardId, cdId);
        Test.stopTest();

        BusinessCard__c card = [SELECT Status__c, Lead__c, Company__c, Last_Name__c
                                FROM BusinessCard__c WHERE Id = :enq.businessCardId];
        System.assertEquals('LeadCreated', card.Status__c);
        System.assertNotEquals(null, card.Lead__c);
        System.assertEquals('TestCo', card.Company__c);
        System.assertEquals('홍길동', card.Last_Name__c);

        // Lead에도 ContentDocumentLink 추가됨
        Integer leadLinkCount = [SELECT COUNT() FROM ContentDocumentLink
                                 WHERE LinkedEntityId = :card.Lead__c AND ContentDocumentId = :cdId];
        System.assertEquals(1, leadLinkCount, 'Lead 페이지 미리보기용 ContentDocumentLink');
    }

    @isTest static void processInBackgroundNotBusinessCardMarksFailed() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Id cdId = linkedContentDocumentId(enq.businessCardId);

        BC_LLMResponse r = new BC_LLMResponse();
        r.isBusinessCard = false;
        r.rawText = 'random photo';
        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.responseToReturn = r;
        AutoLeadByBC_Service.invoker = mock;

        Test.startTest();
        AutoLeadByBC_Service.processInBackground(enq.businessCardId, cdId);
        Test.stopTest();

        BusinessCard__c card = [SELECT Status__c, Lead__c, Raw_OCR_Text__c FROM BusinessCard__c
                                WHERE Id = :enq.businessCardId];
        System.assertEquals('Failed', card.Status__c);
        System.assertEquals(null, card.Lead__c);
        System.assertEquals('random photo', card.Raw_OCR_Text__c);
    }

    @isTest static void processInBackgroundLLMExceptionMarksFailed() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Id cdId = linkedContentDocumentId(enq.businessCardId);

        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.exceptionToThrow = new BC_PromptInvoker.BC_PromptInvokerException('mock LLM down');
        AutoLeadByBC_Service.invoker = mock;

        Test.startTest();
        AutoLeadByBC_Service.processInBackground(enq.businessCardId, cdId);
        Test.stopTest();

        BusinessCard__c card = [SELECT Status__c, Failure_Reason__c FROM BusinessCard__c
                                WHERE Id = :enq.businessCardId];
        System.assertEquals('Failed', card.Status__c);
        System.assert(card.Failure_Reason__c.contains('LLM_FAILURE'));
        System.assert(card.Failure_Reason__c.contains('mock LLM down'));
    }

    @isTest static void duplicateMatchesAreFlaggedOnLead() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Id cdId = linkedContentDocumentId(enq.businessCardId);

        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.responseToReturn = buildHappyResponse();
        AutoLeadByBC_Service.invoker = mock;

        Lead existing = new Lead(Company = 'Acme', LastName = '홍', Email = 'pre@test.com');
        insert existing;
        StubChecker stub = new StubChecker();
        stub.stubMatchedIds = new List<Id>{ existing.Id };
        AutoLeadByBC_Service.checker = stub;

        Test.startTest();
        AutoLeadByBC_Service.processInBackground(enq.businessCardId, cdId);
        Test.stopTest();

        BusinessCard__c card = [SELECT Lead__c FROM BusinessCard__c WHERE Id = :enq.businessCardId];
        Lead lead = [SELECT Duplicate_Suspect__c, Duplicate_Suspect_Info__c FROM Lead WHERE Id = :card.Lead__c];
        System.assertEquals(true, lead.Duplicate_Suspect__c);
        System.assert(lead.Duplicate_Suspect_Info__c.contains((String) existing.Id));
    }

    @isTest static void fetchResultReturnsLeadCreatedDto() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Id cdId = linkedContentDocumentId(enq.businessCardId);

        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.responseToReturn = buildHappyResponse();
        AutoLeadByBC_Service.invoker = mock;
        AutoLeadByBC_Service.checker = new StubChecker();

        AutoLeadByBC_Service.processInBackground(enq.businessCardId, cdId);

        Test.startTest();
        AutoLeadByBC_Service.ResultDTO dto = AutoLeadByBC_Service.fetchResult(enq.businessCardId);
        Test.stopTest();

        System.assertEquals('LeadCreated', dto.status);
        System.assertEquals('TestCo', dto.company);
        System.assertEquals('홍길동', dto.lastName);
        System.assertEquals('대표이사', dto.title);
        System.assertNotEquals(null, dto.leadId);
        System.assert(dto.missingFields.contains('website'), 'website confidence=0이라 missing에 포함');
    }

    @isTest static void fetchResultReturnsFailedDtoWithCode() {
        AutoLeadByBC_Service.skipQueueable = true;
        AutoLeadByBC_Service.ResultDTO enq =
            AutoLeadByBC_Service.enqueueProcessing('test.jpg', fakeBase64());
        Id cdId = linkedContentDocumentId(enq.businessCardId);

        BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
        mock.exceptionToThrow = new BC_PromptInvoker.BC_PromptInvokerException('LLM down');
        AutoLeadByBC_Service.invoker = mock;

        AutoLeadByBC_Service.processInBackground(enq.businessCardId, cdId);

        Test.startTest();
        AutoLeadByBC_Service.ResultDTO dto = AutoLeadByBC_Service.fetchResult(enq.businessCardId);
        Test.stopTest();

        System.assertEquals('Failed', dto.status);
        System.assertEquals('LLM_FAILURE', dto.failureCode);
        System.assert(dto.failureMessage.contains('LLM down'));
    }

    @isTest static void fetchResultNullInputFails() {
        Test.startTest();
        AutoLeadByBC_Service.ResultDTO dto = AutoLeadByBC_Service.fetchResult(null);
        Test.stopTest();
        System.assertEquals('Failed', dto.status);
        System.assertEquals('INVALID_INPUT', dto.failureCode);
    }
}
