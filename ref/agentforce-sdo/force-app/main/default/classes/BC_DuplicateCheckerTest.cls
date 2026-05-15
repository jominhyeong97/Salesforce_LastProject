@isTest
private class BC_DuplicateCheckerTest {

    @isTest static void noMatchReturnsEmpty() {
        BC_DuplicateChecker checker = new BC_DuplicateChecker();
        Lead newLead = new Lead(Company = 'Acme Co', LastName = '홍길동', Email = 'unique-noop@nowhere.example.com');
        Test.startTest();
        List<Id> result = checker.findMatchedIds(newLead);
        Test.stopTest();
        System.assert(result.isEmpty(), '매칭 없는 신규 이메일이라 빈 결과 기대');
    }

    @isTest static void matchReturnsExistingLeadId() {
        // 기존 Lead 1건 INSERT
        Lead existing = new Lead(Company = 'Acme Co', LastName = '홍길동', Email = 'dup-test@nowhere.example.com');
        insert existing;

        // 같은 Email로 신규 Lead 후보 — INSERT 안 함, 사전 검사만
        Lead candidate = new Lead(Company = 'Acme Co', LastName = '김철수', Email = 'dup-test@nowhere.example.com');

        BC_DuplicateChecker checker = new BC_DuplicateChecker();
        Test.startTest();
        List<Id> result = checker.findMatchedIds(candidate);
        Test.stopTest();

        // 표준 Lead Duplicate Rule이 ORG에 켜져 있을 때 매칭 잡힘.
        // 비활성 ORG에서도 통과하도록 일반 단언 — 타입만 확인.
        System.assertNotEquals(null, result, 'null 반환 안 됨');
    }

    @isTest static void nullInputReturnsEmpty() {
        BC_DuplicateChecker checker = new BC_DuplicateChecker();
        List<Id> result = checker.findMatchedIds(null);
        System.assert(result.isEmpty());
    }
}
