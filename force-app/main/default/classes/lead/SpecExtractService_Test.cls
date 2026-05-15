@IsTest
private class SpecExtractService_Test {

    @IsTest
    static void testAi_full() {
        SpecExtractInvoker.mockJsonResponse =
            '{"company":"한라정공","contactName":"박 과장","phone":"010-1111-2222","partName":"베어링 6204","quantity":"100","requestedDate":"다음달 말까지"}';
        Map<String, String> r = SpecExtractService.extract(
            '베어링 견적 문의', '한라정공 박과장입니다. 010-1111-2222\n베어링 6204 100개 다음달 말까지 부탁드립니다.'
        );
        System.assertEquals('한라정공', r.get('company'));
        System.assertEquals('박 과장', r.get('contactName'));
        System.assertEquals('010-1111-2222', r.get('phone'));
        System.assertEquals('베어링 6204', r.get('partName'));
        System.assertEquals('100', r.get('quantity'));
        System.assertEquals('다음달 말까지', r.get('requestedDate'));
        System.assertEquals('ai', SpecExtractService.lastSource);
    }

    @IsTest
    static void testAi_codeFence() {
        SpecExtractInvoker.mockJsonResponse =
            '```json\n{"company":"테스트","contactName":"","phone":"010-3333-4444","partName":"","quantity":"","requestedDate":""}\n```';
        Map<String, String> r = SpecExtractService.extract(
            'subj', '본문 010-3333-4444 입니다.'
        );
        System.assertEquals('테스트', r.get('company'));
        System.assertEquals('010-3333-4444', r.get('phone'));
        System.assertEquals('ai', SpecExtractService.lastSource);
    }

    @IsTest
    static void testFallback_whenAiException() {
        SpecExtractInvoker.mockExceptionMessage = 'LLM down';
        Map<String, String> r = SpecExtractService.extract(
            'subj', '대성기공 김 대리 010-1234-5678, 단조품 50개'
        );
        // fallback 은 CallMemoExtract 결과 사용 — CallMemoExtract도 AI 라 정규식만 fallback 으로 보장
        System.assertEquals('fallback', SpecExtractService.lastSource);
    }

    @IsTest
    static void testEmpty_returnsEmpty() {
        Map<String, String> r = SpecExtractService.extract('subj', '');
        System.assertEquals('', r.get('phone'));
        System.assertEquals('empty', SpecExtractService.lastSource);
    }

    @IsTest
    static void testAi_allBlank_fallsBack() {
        // AI 가 모든 필드 빈문자열 반환 → fallback
        SpecExtractInvoker.mockJsonResponse =
            '{"company":"","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}';
        Map<String, String> r = SpecExtractService.extract(
            'subj', '현대모비스 010-1234-5678, 베어링 100개'
        );
        // CallMemoExtract 도 AI 호출하지만 test 컨텍스트에선 default mock 으로 빈 응답 → 그 결과 fallback
        System.assertEquals('fallback', SpecExtractService.lastSource);
    }

    @IsTest
    static void testAi_partialBlankFields_filledFromBackup() {
        // AI 가 일부만 채움 → 빈 필드는 CallMemoExtract backup 으로 보강
        SpecExtractInvoker.mockJsonResponse =
            '{"company":"한라정공","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}';
        // CallMemoExtract 도 AI mock 없이 default 빈 응답 → 정규식 fallback 으로 phone 추출 보장
        Map<String, String> r = SpecExtractService.extract(
            '베어링 견적', '한라정공입니다. 010-7777-8888 베어링 50개 부탁드립니다.'
        );
        System.assertEquals('한라정공', r.get('company'));
        // backup(=CallMemoExtract default mock → empty + 정규식 fallback) — phone 은 정규식이 잡음
        System.assertEquals('010-7777-8888', r.get('phone'));
        System.assertEquals('ai', SpecExtractService.lastSource);
    }

    @IsTest
    static void testStripCodeFences_directly_handlesPlainAndFenced() {
        // 코드 펜스 없는 정상 JSON
        SpecExtractInvoker.mockJsonResponse =
            '{"company":"NoFence","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}';
        Map<String, String> r1 = SpecExtractService.extract('s', 'b');
        System.assertEquals('NoFence', r1.get('company'));

        // 펜스 + json 키워드
        SpecExtractInvoker.mockJsonResponse =
            '```json\n{"company":"WithFence","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}\n```';
        Map<String, String> r2 = SpecExtractService.extract('s', 'b');
        System.assertEquals('WithFence', r2.get('company'));

        // 펜스 + JSON(대문자)
        SpecExtractInvoker.mockJsonResponse =
            '```JSON\n{"company":"UpperFence","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}\n```';
        Map<String, String> r3 = SpecExtractService.extract('s', 'b');
        System.assertEquals('UpperFence', r3.get('company'));
    }

    @IsTest
    static void testAi_nullBody_emptyResult() {
        Map<String, String> r = SpecExtractService.extract('subj', null);
        for (String k : new String[]{'company','contactName','phone','partName','quantity','requestedDate'}) {
            System.assertEquals('', r.get(k));
        }
        System.assertEquals('empty', SpecExtractService.lastSource);
    }

    @IsTest
    static void testAi_invalidJson_fallsBack() {
        SpecExtractInvoker.mockJsonResponse = 'broken json {';
        Map<String, String> r = SpecExtractService.extract(
            'subj', '대성기공 010-1234-5678'
        );
        // parse 실패 → exception → fallback
        System.assertEquals('fallback', SpecExtractService.lastSource);
        System.assertEquals('010-1234-5678', r.get('phone'));
    }

    @IsTest
    static void testAi_nullSubject_ok() {
        SpecExtractInvoker.mockJsonResponse =
            '{"company":"NoSubj","contactName":"","phone":"010-2222-3333","partName":"","quantity":"","requestedDate":""}';
        Map<String, String> r = SpecExtractService.extract(null, '010-2222-3333');
        System.assertEquals('NoSubj', r.get('company'));
        System.assertEquals('010-2222-3333', r.get('phone'));
        System.assertEquals('ai', SpecExtractService.lastSource);
    }
}
