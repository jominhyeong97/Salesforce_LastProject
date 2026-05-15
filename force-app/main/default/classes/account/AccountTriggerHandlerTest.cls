/**
 * AccountTriggerHandlerTest
 * 한국 사업자번호 검증/포맷팅 단위 테스트.
 * Valid 번호 (직접 체크섬 검증): 1208147521, 2208179357
 * Invalid 번호: 1234567890
 */
@IsTest
private class AccountTriggerHandlerTest {

    // 시나리오: 유효한 사업자번호 insert → 자동 하이픈 포맷팅 적용
    @IsTest
    static void testValidNumber_FormatsHyphen() {
        Account acc = new Account(Name = '테스트 거래처', Business_Number__c = '1208147521');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account refreshed = [SELECT Business_Number__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('120-81-47521', refreshed.Business_Number__c, '유효 번호는 XXX-XX-XXXXX 형식으로 저장되어야 한다');
    }

    // 시나리오: 이미 하이픈 포함된 번호 insert → 정규화 후 동일 출력
    @IsTest
    static void testValidNumber_AlreadyHyphenated() {
        Account acc = new Account(Name = '하이픈 거래처', Business_Number__c = '120-81-47521');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account refreshed = [SELECT Business_Number__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('120-81-47521', refreshed.Business_Number__c, '하이픈 포함 입력도 동일 결과');
    }

    // 시나리오: 자릿수 부족 → DmlException, 한국어 에러 메시지
    @IsTest
    static void testInvalidLength() {
        Account acc = new Account(Name = '짧은번호', Business_Number__c = '12345');
        DmlException caught;

        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, '자릿수 오류는 DmlException 발생');
        System.assert(caught.getMessage().contains('10자리'), '에러 메시지에 "10자리" 포함되어야 한다');
    }

    // 시나리오: 형식은 10자리지만 체크섬 오류 → DmlException
    @IsTest
    static void testInvalidChecksum() {
        Account acc = new Account(Name = '체크섬 오류', Business_Number__c = '1234567890');
        DmlException caught;

        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, '체크섬 실패는 DmlException 발생');
        System.assert(caught.getMessage().contains('체크섬'), '에러 메시지에 "체크섬" 포함되어야 한다');
    }

    // 시나리오: Business_Number__c 가 null → 검증 skip, insert 성공
    @IsTest
    static void testBlankNumber_Skipped() {
        Account acc = new Account(Name = '빈 사업자번호', Business_Number__c = null);

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account refreshed = [SELECT Business_Number__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, refreshed.Business_Number__c, 'null 값은 그대로 저장');
    }

    // 시나리오: update 시 사업자번호 변경 없으면 재검증 skip (이름만 수정)
    @IsTest
    static void testUpdate_NoChange_NoRevalidation() {
        Account acc = new Account(Name = '이름변경전', Business_Number__c = '1208147521');
        insert acc;

        Account refreshed = [SELECT Id, Name, Business_Number__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('120-81-47521', refreshed.Business_Number__c, '초기 insert 시 포맷팅 확인');

        refreshed.Name = '이름변경후';

        Test.startTest();
        update refreshed;
        Test.stopTest();

        Account after = [SELECT Name, Business_Number__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('이름변경후', after.Name);
        System.assertEquals('120-81-47521', after.Business_Number__c, '미변경 시 동일 값 유지');
    }

    // 시나리오: 두 번째 valid 번호(2208179357)로 알고리즘 직접 호출 검증
    @IsTest
    static void testIsValidBusinessNumber_DirectCalls() {
        System.assertEquals(true, AccountTriggerHandler.isValidBusinessNumber('1208147521'), '1208147521은 valid');
        System.assertEquals(true, AccountTriggerHandler.isValidBusinessNumber('2208179357'), '2208179357은 valid');
        System.assertEquals(false, AccountTriggerHandler.isValidBusinessNumber('1234567890'), '1234567890은 invalid');
        System.assertEquals(false, AccountTriggerHandler.isValidBusinessNumber('12345'), '자릿수 부족은 invalid');
        System.assertEquals(false, AccountTriggerHandler.isValidBusinessNumber(null), 'null은 invalid');
        System.assertEquals(false, AccountTriggerHandler.isValidBusinessNumber(''), '빈 문자열은 invalid');
    }
}
