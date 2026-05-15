/**
 * AccountTriggerHandler
 * 한국 사업자번호(Business_Number__c) 체크섬 검증 + 자동 하이픈 포맷팅.
 * FR-LOC-004. with sharing, bulkified.
 */
public with sharing class AccountTriggerHandler {

    private static final List<Integer> WEIGHTS = new List<Integer>{1, 3, 7, 1, 3, 7, 1, 3, 5};

    public static void handle(List<Account> newList, Map<Id, Account> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Boolean isUpdate = (oldMap != null);

        for (Account acc : newList) {
            String raw = acc.Business_Number__c;

            // blank → skip
            if (String.isBlank(raw)) {
                continue;
            }

            // update 시 변경 없으면 skip (재검증 비용 방지)
            if (isUpdate) {
                Account old = oldMap.get(acc.Id);
                if (old != null && old.Business_Number__c == raw) {
                    continue;
                }
            }

            String digits = stripNonDigits(raw);
            if (digits.length() != 10) {
                acc.Business_Number__c.addError('사업자번호는 10자리 숫자여야 합니다.');
                continue;
            }

            if (!isValidBusinessNumber(digits)) {
                acc.Business_Number__c.addError('사업자번호가 올바르지 않습니다 (체크섬 오류).');
                continue;
            }

            acc.Business_Number__c = formatWithHyphen(digits);
        }
    }

    @TestVisible
    private static Boolean isValidBusinessNumber(String raw) {
        if (String.isBlank(raw)) {
            return false;
        }
        String digits = stripNonDigits(raw);
        if (digits.length() != 10) {
            return false;
        }

        Integer sumValue = 0;
        for (Integer i = 0; i < 9; i++) {
            Integer d = Integer.valueOf(digits.substring(i, i + 1));
            sumValue += d * WEIGHTS[i];
        }
        Integer eighth = Integer.valueOf(digits.substring(8, 9));
        sumValue += (eighth * 5) / 10;

        Integer check = (10 - Math.mod(sumValue, 10));
        check = Math.mod(check, 10);

        Integer last = Integer.valueOf(digits.substring(9, 10));
        return check == last;
    }

    @TestVisible
    private static String formatWithHyphen(String digits) {
        if (String.isBlank(digits) || digits.length() != 10) {
            return digits;
        }
        return digits.substring(0, 3) + '-' + digits.substring(3, 5) + '-' + digits.substring(5, 10);
    }

    @TestVisible
    private static String stripNonDigits(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        return raw.replaceAll('[^0-9]', '');
    }
}
