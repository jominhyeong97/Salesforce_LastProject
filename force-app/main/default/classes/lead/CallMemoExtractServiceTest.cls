@isTest
private class CallMemoExtractServiceTest {

    // ─────────────────────────────────────────────────────────────────────
    // AI path (mock JSON 우회)
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testAiSuccess_fullExtract() {
        CallMemoExtractService.mockJsonResponse =
            '{"company":"현대모비스","contactName":"김 대리","contactTitle":"대리","phone":"010-1234-5678","partName":"베어링 6204","quantity":"100","requestedDate":"다음달 말까지"}';
        Map<String, String> r = CallMemoExtractService.extract(
            '현대모비스 김 대리 010-1234-5678, 베어링 6204 100개, 다음달 말까지'
        );
        System.assertEquals('현대모비스', r.get('company'));
        System.assertEquals('김 대리', r.get('contactName'));
        System.assertEquals('대리', r.get('contactTitle'));
        System.assertEquals('010-1234-5678', r.get('phone'));
        System.assertEquals('베어링 6204', r.get('partName'));
        System.assertEquals('100', r.get('quantity'));
        System.assertEquals('다음달 말까지', r.get('requestedDate'));
        System.assertEquals('ai', CallMemoExtractService.lastSource);
    }

    @isTest
    static void testAiSuccess_partialFillsFromRegex() {
        // AI 가 phone 만 채우고 나머지 blank → regex 가 보강
        CallMemoExtractService.mockJsonResponse =
            '{"company":"","contactName":"","contactTitle":"","phone":"010-9999-8888","partName":"","quantity":"","requestedDate":""}';
        Map<String, String> r = CallMemoExtractService.extract(
            '대성기공 박과장 010-9999-8888, 샤프트 50EA'
        );
        System.assertEquals('010-9999-8888', r.get('phone'));
        // company 는 AI 빈 → regex 가 '대성기공' 으로 채워야 함
        System.assertEquals('대성기공', r.get('company'));
        // 입력 "박과장"은 공백 없이 적힘 → 원문 보존
        System.assertEquals('박과장', r.get('contactName'));
        System.assertEquals('과장', r.get('contactTitle'));
        System.assertEquals('샤프트', r.get('partName'));
        System.assertEquals('50', r.get('quantity'));
        System.assertEquals('ai', CallMemoExtractService.lastSource);
    }

    @isTest
    static void testAiCodeFenceStripped() {
        // D26 — AI 가 코드 펜스로 감싼 응답을 stripCodeFences 가 벗기는지
        CallMemoExtractService.mockJsonResponse =
            '```json\n{"company":"테스트","contactName":"","phone":"010-1111-2222","partName":"","quantity":"","requestedDate":""}\n```';
        Map<String, String> r = CallMemoExtractService.extract('테스트 010-1111-2222');
        System.assertEquals('테스트', r.get('company'));
        System.assertEquals('010-1111-2222', r.get('phone'));
        System.assertEquals('ai', CallMemoExtractService.lastSource);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Fallback path (LLM 실패 시 정규식)
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testFallback_whenLlmThrows() {
        CallMemoExtractService.mockExceptionMessage = 'LLM 호출 실패 시뮬';
        Map<String, String> r = CallMemoExtractService.extract(
            '현대모비스 김 대리 010-1234-5678, 베어링 6204 100개, 다음달 말까지'
        );
        System.assertEquals('현대모비스', r.get('company'));
        System.assertEquals('김 대리', r.get('contactName'));
        System.assertEquals('010-1234-5678', r.get('phone'));
        System.assertEquals('100', r.get('quantity'));
        System.assertEquals('fallback', CallMemoExtractService.lastSource);
    }

    @isTest
    static void testFallback_whenAiReturnsAllBlank() {
        CallMemoExtractService.mockJsonResponse =
            '{"company":"","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}';
        Map<String, String> r = CallMemoExtractService.extract(
            '현대모비스 김 대리 010-1234-5678, 베어링 6204 100개, 다음달 말까지'
        );
        // AI 가 모든 필드 blank → fallback regex
        System.assertEquals('010-1234-5678', r.get('phone'));
        System.assertEquals('현대모비스', r.get('company'));
        System.assertEquals('fallback', CallMemoExtractService.lastSource);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Edge cases
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testBlankMemo() {
        Map<String, String> r = CallMemoExtractService.extract('');
        System.assertEquals('', r.get('company'));
        System.assertEquals('', r.get('phone'));
        System.assertEquals('empty', CallMemoExtractService.lastSource);
    }

    @isTest
    static void testNullMemo() {
        Map<String, String> r = CallMemoExtractService.extract(null);
        System.assertEquals('', r.get('phone'));
        System.assertEquals('empty', CallMemoExtractService.lastSource);
    }

    @isTest
    static void testPhoneOnly_regexFallback() {
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract('연락처 010-9876-5432 입니다');
        System.assertEquals('010-9876-5432', r.get('phone'));
        System.assertEquals('fallback', CallMemoExtractService.lastSource);
    }

    @isTest
    static void testQuantityWithEa_regexFallback() {
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract('샤프트 50EA 필요');
        System.assertEquals('50', r.get('quantity'));
        System.assertEquals('샤프트', r.get('partName'));
    }

    // ─────────────────────────────────────────────────────────────────────
    // 담당자/직급 분리 (한국식 표기 보존 + 호칭 씨/님 제거)
    // ─────────────────────────────────────────────────────────────────────

    @isTest
    static void testContact_fullNameWithSshi_regexFallback() {
        // "김국진씨" → contactName="김국진" (호칭 제거), contactTitle=""
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract(
            '포스코 김국진씨가 12월30일까지 베어링 200개 납품되냐고 물어봄'
        );
        System.assertEquals('김국진', r.get('contactName'));
        System.assertEquals('', r.get('contactTitle'));
    }

    @isTest
    static void testContact_surnameWithJangNim_regexFallback() {
        // "김사장님" → contactName="김사장" (님 제거), contactTitle="사장"
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract(
            '포스코 김사장님이 12월30일까지 베어링 200개 납품되냐고 물어봄'
        );
        System.assertEquals('김사장', r.get('contactName'));
        System.assertEquals('사장', r.get('contactTitle'));
    }

    @isTest
    static void testContact_fullNameWithTitle_regexFallback() {
        // "박민수 과장" → contactName="박민수" (이름만), contactTitle="과장"
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract(
            '현대 박민수 과장 010-1111-2222'
        );
        System.assertEquals('박민수', r.get('contactName'));
        System.assertEquals('과장', r.get('contactTitle'));
    }

    @isTest
    static void testContact_fullNameSurnameAndTitleNoSpace_regexFallback() {
        // "김국진사장" → contactName="김국진", contactTitle="사장"
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract(
            '대성기공 김국진사장 010-2222-3333'
        );
        System.assertEquals('김국진', r.get('contactName'));
        System.assertEquals('사장', r.get('contactTitle'));
    }

    @isTest
    static void testContact_surnameWithSpaceTitle_regexFallback() {
        // "김 대리" → contactName="김 대리" (공백 유지), contactTitle="대리"
        CallMemoExtractService.mockExceptionMessage = 'force fallback';
        Map<String, String> r = CallMemoExtractService.extract(
            '현대모비스 김 대리 010-1234-5678'
        );
        System.assertEquals('김 대리', r.get('contactName'));
        System.assertEquals('대리', r.get('contactTitle'));
    }
}
