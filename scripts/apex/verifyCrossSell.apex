// E2E: GetCrossSellCandidates 5번째 Action
// 시드의 가장 많이 발주한 Account 찾기 → cross-sell 후보 산출
List<AggregateResult> top = [
    SELECT AccountId aid, COUNT(Id) cnt
    FROM Order
    WHERE AccountId != null
    GROUP BY AccountId
    ORDER BY COUNT(Id) DESC
    LIMIT 1
];
if (top.isEmpty()) {
    System.debug('Order 데이터 없음');
    return;
}
Id aid = (Id) top[0].get('aid');
Account a = [SELECT Id, Name FROM Account WHERE Id = :aid LIMIT 1];
System.debug('=== Target Account: ' + a.Name + ' (' + top[0].get('cnt') + ' Orders) ===');

GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
req.accountId = aid;
req.maxResults = 5;

List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
    new List<GetCrossSellCandidatesAction.Request>{ req });

GetCrossSellCandidatesAction.Response r = outs[0];
System.debug('found=' + r.found + ', count=' + r.candidateCount);
System.debug('summary=' + r.summary);
System.debug('candidates (parse 후 첫 3개):');
List<Object> cands = (List<Object>) JSON.deserializeUntyped(r.candidatesJson);
Integer i = 0;
for (Object o : cands) {
    if (i >= 3) break;
    System.debug('  ' + JSON.serializePretty(o));
    i++;
}

System.debug('=== AgentforceInputBar 라우팅 검증 ===');
AgentforceInputBarService.AgentResponse a1 = AgentforceInputBarService.ask(
    a.Name + ' 에게 추천 부품', null);
System.debug('action=' + a1.action);
System.debug('message=' + a1.message);
