// E2E: AgentforceInputBar 라우팅 6가지 (4 키워드 카테고리 + 2 LLM fallback)
List<String> qs = new List<String>{
    '안녕하세요',
    '오늘 우선순위 알려줘',
    '지난주 매출은 얼마야',
    '무엇을 도와줄 수 있어',
    '태양산업 미수금 보여줘',
    '거긴 더 팔만한 부품 뭐 있을까'
};
for (String q : qs) {
    AgentforceInputBarService.AgentResponse r = AgentforceInputBarService.ask(q, null);
    System.debug('---');
    System.debug('Q: ' + q);
    System.debug('  action=' + r.action);
    System.debug('  msg=' + r.message);
}
