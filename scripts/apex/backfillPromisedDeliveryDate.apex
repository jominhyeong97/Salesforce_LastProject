// D38 — 약속 납기일 backfill.
// 기존 Opp 중 '발굴'이 아닌(이미 견적 단계 이상 진입한) Opp 에 Promised_Delivery_Date__c 채움.
// 룰: Order 가 이미 있으면 Order.EndDate 그대로 차용, 없으면 CloseDate - 7일 (납기는 종료일 직전 가정).

List<Opportunity> opps = [
    SELECT Id, StageName, CloseDate, Promised_Delivery_Date__c
    FROM Opportunity
    WHERE StageName != '발굴'
      AND Promised_Delivery_Date__c = null
    LIMIT 500
];
System.debug('D38 backfill candidates: ' + opps.size());
if (opps.isEmpty()) return;

Set<Id> oppIds = new Map<Id, Opportunity>(opps).keySet();

// Opp 별 가장 빠른 Order.EndDate (있으면) 매핑
Map<Id, Date> oppToEndDate = new Map<Id, Date>();
for (Order ord : [
    SELECT Opportunity__c, EndDate
    FROM Order
    WHERE Opportunity__c IN :oppIds AND EndDate != null
    ORDER BY CreatedDate ASC
]) {
    if (!oppToEndDate.containsKey(ord.Opportunity__c)) {
        oppToEndDate.put(ord.Opportunity__c, ord.EndDate);
    }
}

List<Opportunity> toUpdate = new List<Opportunity>();
for (Opportunity o : opps) {
    Date promised = oppToEndDate.get(o.Id);
    if (promised == null) {
        promised = (o.CloseDate != null) ? o.CloseDate.addDays(-7) : Date.today().addDays(30);
    }
    o.Promised_Delivery_Date__c = promised;
    toUpdate.add(o);
}

Database.SaveResult[] results = Database.update(toUpdate, false);
Integer ok = 0, fail = 0;
for (Database.SaveResult r : results) {
    if (r.isSuccess()) ok++;
    else { fail++; System.debug('FAIL: ' + r.getErrors()); }
}
System.debug('D38 backfill done. ok=' + ok + ' fail=' + fail);
