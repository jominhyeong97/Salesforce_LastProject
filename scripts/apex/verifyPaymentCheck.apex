// E2E: 챗봇이 PaymentCheck 라우팅 + 실 LLM 응답 생성하는지 검증
// 실행: sf apex run --file scripts/apex/verifyPaymentCheck.apex --target-org My_Org

System.debug('═══════════════════════════════════════');
System.debug('PaymentCheck E2E 검증 시작');
System.debug('═══════════════════════════════════════');

List<String> queries = new List<String>{
    '오늘 입금 들어온 거 있어?',
    '이번주 회수 어땠어?',
    '미수금 큰 데 어디야?'
};

for (String q : queries) {
    System.debug('───────────────────────────────────────');
    System.debug('▶ 질의: ' + q);
    AgentforceInputBarService.AgentResponse r = AgentforceInputBarService.ask(q, null);
    System.debug('  action  : ' + r.action);
    System.debug('  message : ' + r.message);
    if (r.detailsJson != null && r.detailsJson.length() > 200) {
        System.debug('  detailsJson (앞 200): ' + r.detailsJson.substring(0, 200) + '...');
    } else {
        System.debug('  detailsJson: ' + r.detailsJson);
    }
}

// 특정 고객사 — 시드 데이터에 있는 회사명 사용
System.debug('───────────────────────────────────────');
List<Account> sample = [SELECT Id, Name FROM Account WHERE Total_AR__c > 0 ORDER BY Total_AR__c DESC LIMIT 1];
if (!sample.isEmpty()) {
    String acctName = sample[0].Name;
    String q = acctName + ' 잔액 얼마야?';
    System.debug('▶ 질의: ' + q);
    AgentforceInputBarService.AgentResponse r = AgentforceInputBarService.ask(q, null);
    System.debug('  action  : ' + r.action);
    System.debug('  message : ' + r.message);
}

System.debug('═══════════════════════════════════════');
System.debug('완료');
