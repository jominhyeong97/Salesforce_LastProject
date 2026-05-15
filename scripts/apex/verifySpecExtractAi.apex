// E2E: SpecExtract Prompt Builder 실 LLM 호출 검증
String subj = '베어링 견적 요청';
String body = '안녕하세요, 한라정공의 박과장입니다.\n' +
              '저희 측 신규 라인 셋업 관련 베어링 6204 100개 견적 부탁드립니다.\n' +
              '연락처 010-7777-8888 이며 납기는 다음달 말까지 부탁드립니다.\n' +
              '감사합니다.\n— 한라정공 박과장';

Map<String, String> r = SpecExtractService.extract(subj, body);
System.debug('lastSource=' + SpecExtractService.lastSource);
for (String k : new String[]{'company','contactName','phone','partName','quantity','requestedDate'}) {
    System.debug('  ' + k + ' = "' + r.get(k) + '"');
}
