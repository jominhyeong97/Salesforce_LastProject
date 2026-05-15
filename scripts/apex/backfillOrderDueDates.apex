// Order.EndDate 백필 — 시연용 결정적 분포
// 위험 5건 (PoNumber 끝 6 + InProgress): today + 1~3일 (임박)
// 대형지연 5건 (끝 9 + InProgress): today - 1~5일 (OVERDUE)
// 나머지: EffectiveDate + 30일

List<Order> orders = [
    SELECT Id, PoNumber, Production_Status__c, EffectiveDate, EndDate
    FROM Order
    WHERE PoNumber LIKE 'PO-2026-%'
];

Date today = Date.today();
Integer riskIdx = 0, longIdx = 0, safeIdx = 0;
List<Order> toUpdate = new List<Order>();

for (Order o : orders) {
    if (o.PoNumber == null) continue;
    String last = o.PoNumber.right(1);
    Boolean isInProg = o.Production_Status__c == 'InProgress';

    Date newDate;
    if (last == '6' && isInProg) {
        // 임박 D-1/D-2/D-3
        newDate = today.addDays(Math.mod(riskIdx, 3) + 1);
        riskIdx++;
    } else if (last == '9' && isInProg) {
        // OVERDUE D+1 ~ D+5
        newDate = today.addDays(-1 * (Math.mod(longIdx, 5) + 1));
        longIdx++;
    } else {
        // 나머지 — today 기준 +14~+30일 사이로 분산 (여유)
        newDate = today.addDays(14 + Math.mod(safeIdx, 17));
        safeIdx++;
    }
    o.EndDate = newDate;
    toUpdate.add(o);
}

update toUpdate;
System.debug('=== Updated EndDate on ' + toUpdate.size() + ' Orders. risk=' + riskIdx + ' overdue=' + longIdx);

Integer overdue = 0, imminent = 0, safe = 0;
for (Order o : [SELECT EndDate FROM Order WHERE PoNumber LIKE 'PO-2026-%' AND EndDate != null]) {
    Integer days = Date.today().daysBetween(o.EndDate);
    if (days < 0) overdue++;
    else if (days <= 3) imminent++;
    else safe++;
}
System.debug('=== overdue: ' + overdue + ', imminent: ' + imminent + ', safe: ' + safe);
