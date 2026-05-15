/**
 * BusinessLicensePromptService_Test — 사업자등록증 OCR 서비스 테스트.
 *
 * 전략:
 *   - ConnectApi 호출은 실제 org 연결 없이 테스트 불가 → BusinessLicensePromptInvoker
 *     의 mockJsonResponse / mockExceptionMessage 정적 필드로 우회.
 *   - 각 테스트는 별도 Apex 트랜잭션이므로 static field가 자동 격리됨.
 */
@isTest
private class BusinessLicensePromptService_Test {

    // 사업자번호는 AccountTriggerHandler 체크섬 통과하는 valid 값 사용
    private static final String JSON_FULL =
        '{"businessNumber":"120-81-47521","companyName":"주식회사 샤프플로우",' +
        '"ceoName":"김철수","address":"서울시 강남구 테헤란로 123","raw_text":"raw"}';

    private static final String JSON_PARTIAL =
        '{"businessNumber":"220-81-79357","companyName":"부분상사",' +
        '"ceoName":"","address":"","raw_text":"raw"}';

    private static final String JSON_EMPTY =
        '{"businessNumber":"","companyName":"","ceoName":"","address":"","raw_text":""}';

    /** 1×1 흰색 PNG base64. */
    private static final String DUMMY_BASE64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==';

    private static Account makeAccount() {
        Account a = new Account(
            Name               = '기존회사명',
            Business_Number__c = '000-00-00000',
            CEO_Name__c        = '기존대표',
            BillingStreet      = '기존주소'
        );
        insert a;
        return a;
    }

    private static Opportunity makeOpp(Id accountId) {
        Opportunity o = new Opportunity(
            Name      = 'TestOpp',
            AccountId = accountId,
            StageName = '발굴',
            CloseDate = Date.today().addDays(30)
        );
        insert o;
        return o;
    }

    // ─── 1. Success: 4필드 모두 추출 (Account record) ─────────────────
    @isTest
    static void testProcessLicense_Success_OnAccount() {
        Account a = makeAccount();
        BusinessLicensePromptService.mockJsonResponse = JSON_FULL;

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(a.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('success', (String) result.get('status'));
        Assert.areEqual('', (String) result.get('errorMessage'));
        Assert.isNotNull(result.get('ocrJson'), 'ocrJson 보존됨');
        Assert.isNotNull(result.get('contentDocumentId'), 'ContentDocument 생성됨');

        Map<String, Object> extracted = (Map<String, Object>) result.get('extracted');
        Assert.areEqual('120-81-47521', (String) extracted.get('businessNumber'));
        Assert.areEqual('주식회사 샤프플로우', (String) extracted.get('companyName'));

        List<Object> enriched = (List<Object>) result.get('enrichedFields');
        Assert.areEqual(4, enriched.size(), '4필드 모두 enriched');

        Account updated = [SELECT Name, Business_Number__c, CEO_Name__c, BillingStreet
                           FROM Account WHERE Id = :a.Id];
        Assert.areEqual('120-81-47521', updated.Business_Number__c);
        Assert.areEqual('주식회사 샤프플로우', updated.Name);
        Assert.areEqual('김철수', updated.CEO_Name__c);
        Assert.areEqual('서울시 강남구 테헤란로 123', updated.BillingStreet);
    }

    // ─── 2. Success: Opportunity recordId → AccountId 자동 해소 ───────
    @isTest
    static void testProcessLicense_Success_OnOpportunity() {
        Account a = makeAccount();
        Opportunity opp = makeOpp(a.Id);
        BusinessLicensePromptService.mockJsonResponse = JSON_FULL;

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(opp.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('success', (String) result.get('status'));
        Account updated = [SELECT Business_Number__c FROM Account WHERE Id = :a.Id];
        Assert.areEqual('120-81-47521', updated.Business_Number__c);
    }

    // ─── 3. Partial: 2필드만 추출, 나머지는 기존값 유지 ────────────────
    @isTest
    static void testProcessLicense_Partial() {
        Account a = makeAccount();
        BusinessLicensePromptService.mockJsonResponse = JSON_PARTIAL;

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(a.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('partial', (String) result.get('status'));
        List<Object> enriched = (List<Object>) result.get('enrichedFields');
        List<Object> skipped  = (List<Object>) result.get('partialFailures');
        Assert.areEqual(2, enriched.size(), '2필드 enriched');
        Assert.areEqual(2, skipped.size(),  '2필드 skipped');

        Account updated = [SELECT Name, Business_Number__c, CEO_Name__c, BillingStreet
                           FROM Account WHERE Id = :a.Id];
        Assert.areEqual('220-81-79357', updated.Business_Number__c);
        Assert.areEqual('부분상사', updated.Name);
        Assert.areEqual('기존대표', updated.CEO_Name__c, 'CEO 기존값 유지');
        Assert.areEqual('기존주소', updated.BillingStreet, '주소 기존값 유지');
    }

    // ─── 4. Extract Empty: 모든 필드 blank → 별도 status, Account 변경 없음 ─
    @isTest
    static void testProcessLicense_ExtractEmpty() {
        Account a = makeAccount();
        BusinessLicensePromptService.mockJsonResponse = JSON_EMPTY;

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(a.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('extract_empty', (String) result.get('status'));
        String msg = (String) result.get('errorMessage');
        Assert.isTrue(msg.contains('인식하지 못했습니다'), '안내 메시지 포함');
        Assert.isNotNull(result.get('ocrJson'), 'ocrJson 보존(빈 값이지만 JSON은 있음)');

        Account unchanged = [SELECT Name, Business_Number__c FROM Account WHERE Id = :a.Id];
        Assert.areEqual('기존회사명', unchanged.Name);
        Assert.areEqual('000-00-00000', unchanged.Business_Number__c);
    }

    // ─── 5. OCR Error: invoker 예외 → error_ocr ───────────────────────
    @isTest
    static void testProcessLicense_OcrError() {
        Account a = makeAccount();
        BusinessLicensePromptService.mockExceptionMessage = 'simulated LLM failure';

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(a.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('error_ocr', (String) result.get('status'));
        String msg = (String) result.get('errorMessage');
        Assert.isTrue(msg.contains('simulated LLM failure'), '예외 메시지 포함');

        Account unchanged = [SELECT Business_Number__c FROM Account WHERE Id = :a.Id];
        Assert.areEqual('000-00-00000', unchanged.Business_Number__c, 'Account 미변경');
    }

    // ─── 6. No Account: AccountId 없는 Opportunity → error_account ────
    @isTest
    static void testProcessLicense_NoAccount() {
        Opportunity opp = new Opportunity(
            Name      = 'NoAcc',
            StageName = '발굴',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        BusinessLicensePromptService.mockJsonResponse = JSON_FULL;

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(opp.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('error_account', (String) result.get('status'));
    }

    // ─── 7. LLMResponse 파싱 (정상) ──────────────────────────────────
    @isTest
    static void testLLMResponse_FromJson_Valid() {
        BusinessLicenseLLMResponse r = BusinessLicenseLLMResponse.fromJson(JSON_FULL);
        Assert.areEqual('120-81-47521', r.businessNumber);
        Assert.areEqual('주식회사 샤프플로우', r.companyName);
        Assert.areEqual('김철수', r.ceoName);
        Assert.areEqual('서울시 강남구 테헤란로 123', r.address);
        Assert.areEqual('raw', r.rawText);
        Assert.areEqual(JSON_FULL, r.originalJson);
        Assert.isFalse(r.isAllBlank());
    }

    // ─── 8. LLMResponse: 모든 필드 blank ──────────────────────────────
    @isTest
    static void testLLMResponse_AllBlank() {
        BusinessLicenseLLMResponse r = BusinessLicenseLLMResponse.fromJson(JSON_EMPTY);
        Assert.isTrue(r.isAllBlank(), '4필드 모두 blank');
    }

    // ─── 9. LLMResponse: 잘못된 JSON → 예외 ──────────────────────────
    @isTest
    static void testLLMResponse_InvalidJson() {
        Boolean threw = false;
        try {
            BusinessLicenseLLMResponse.fromJson('not a json {');
        } catch (BusinessLicenseLLMResponse.BusinessLicenseLLMResponseException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('not valid JSON'));
        }
        Assert.isTrue(threw, '예외 발생');
    }

    // ─── 10. LLMResponse: 빈 body → 예외 ─────────────────────────────
    @isTest
    static void testLLMResponse_EmptyBody() {
        Boolean threw = false;
        try {
            BusinessLicenseLLMResponse.fromJson('');
        } catch (BusinessLicenseLLMResponse.BusinessLicenseLLMResponseException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    // ─── 11. Account update DML 실패 → error_account (catch path cover) ──
    /**
     * AccountTriggerHandler가 invalid 사업자번호('1234567890')에 대해 addError 호출 →
     * enrichAccount의 update DML 실패 → catch에서 STATUS_ERROR_ACCOUNT 반환.
     */
    @isTest
    static void testProcessLicense_AccountUpdateError() {
        Account a = makeAccount();
        BusinessLicensePromptService.mockJsonResponse =
            '{"businessNumber":"1234567890","companyName":"실패상사",' +
            '"ceoName":"테스트","address":"서울","raw_text":""}';

        Test.startTest();
        Map<String, Object> result =
            BusinessLicensePromptService.processLicense(a.Id, 'license.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.areEqual('error_account', (String) result.get('status'));
        String msg = (String) result.get('errorMessage');
        Assert.isTrue(msg.contains('업데이트 실패'), 'DML 실패 메시지 포함');
    }

    // ─── 12. saveLicenseFile 직접 호출 ───────────────────────────────
    @isTest
    static void testSaveLicenseFile() {
        Account a = makeAccount();

        Test.startTest();
        Id cdId = BusinessLicensePromptService.saveLicenseFile(a.Id, 'biz.jpg', DUMMY_BASE64);
        Test.stopTest();

        Assert.isNotNull(cdId);

        List<ContentVersion> cvs = [
            SELECT Title, PathOnClient FROM ContentVersion
            WHERE PathOnClient = 'biz.jpg' LIMIT 1
        ];
        Assert.areEqual(1, cvs.size(), 'ContentVersion 생성');
        Assert.isTrue(cvs[0].Title.startsWith('사업자등록증_'));

        List<ContentDocumentLink> cdls = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :a.Id AND ContentDocumentId = :cdId
        ];
        Assert.areEqual(1, cdls.size(), 'ContentDocumentLink 생성');
    }
}
