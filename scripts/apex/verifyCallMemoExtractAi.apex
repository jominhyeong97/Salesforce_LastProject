// E2E: CallMemoExtract Prompt Builder template 실 호출 검증
String memo = '현대모비스 김 대리 010-1234-5678, 베어링 6204 100개, 다음달 말까지';
Map<String, String> r = CallMemoExtractService.extract(memo);
System.debug('lastSource=' + CallMemoExtractService.lastSource);
for (String k : new String[]{'company','contactName','phone','partName','quantity','requestedDate'}) {
    System.debug('  ' + k + ' = "' + r.get(k) + '"');
}

System.debug('=== 2nd test — 다른 메모 ===');
String memo2 = '(주)대광건설기계 박과장 010-9876-5432, 단조품 SKD-11 50EA 3주 내 부탁드립니다';
Map<String, String> r2 = CallMemoExtractService.extract(memo2);
System.debug('lastSource=' + CallMemoExtractService.lastSource);
for (String k : new String[]{'company','contactName','phone','partName','quantity','requestedDate'}) {
    System.debug('  ' + k + ' = "' + r2.get(k) + '"');
}
