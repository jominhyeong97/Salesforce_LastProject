/*
 * Day 8 검증 — 시드 100건에 ERP Mock 동기화 적용 후 위험 분포 확인.
 *
 *  실행: sf apex run --file scripts/apex/verifyDay8.apex --target-org My_Org
 *
 *  기대값 (D17-정정 시드 규약):
 *    위험 (≥70): 5건  (PoNumber 끝 '6' + InProgress)
 *    대형지연 (≥85 ⊂ 위험): 5건  (PoNumber 끝 '9' + InProgress)
 *    안전 (<40): 90건
 */

System.debug('=== Day 8 검증 ===');

Integer totalOrders = [SELECT COUNT() FROM Order WHERE PoNumber LIKE 'PO-2026-%'];
System.debug('시드 Order 수: ' + totalOrders + ' (기대 100)');

if (totalOrders == 0) {
    System.debug('⚠️ 시드 데이터 없음. scripts/apex/seedData.apex 먼저 실행 필요.');
    return;
}

Integer beforeNonNull = [SELECT COUNT() FROM Order WHERE PoNumber LIKE 'PO-2026-%' AND Delivery_Risk_Score__c != null];
System.debug('동기화 전 위험점수 채워진 Order: ' + beforeNonNull);

List<OrderErpSyncService.SyncOutcome> outs = OrderErpSyncService.syncAllOpen();
System.debug('syncAllOpen 처리: ' + outs.size() + ' Order (Shipped 제외)');

// 동기화 후 분포 — Apex 측 집계 (SOQL CASE 미지원)
Map<String, Integer> dist = new Map<String, Integer>{
    '대형지연(≥85)' => 0,
    '위험(70-84)'   => 0,
    '주의(40-69)'   => 0,
    '안전(0-39)'    => 0,
    '미동기화'      => 0
};
for (Order o : [SELECT Delivery_Risk_Score__c FROM Order WHERE PoNumber LIKE 'PO-2026-%']) {
    Decimal s = o.Delivery_Risk_Score__c;
    String bucket;
    if (s == null)         bucket = '미동기화';
    else if (s >= 85)      bucket = '대형지연(≥85)';
    else if (s >= 70)      bucket = '위험(70-84)';
    else if (s >= 40)      bucket = '주의(40-69)';
    else                   bucket = '안전(0-39)';
    dist.put(bucket, dist.get(bucket) + 1);
}

System.debug('--- 동기화 후 위험 분포 ---');
for (String k : new List<String>{'대형지연(≥85)','위험(70-84)','주의(40-69)','안전(0-39)','미동기화'}) {
    System.debug('  ' + k + ': ' + dist.get(k) + '건');
}

List<Order> highRisk = [
    SELECT Name, PoNumber, Production_Status__c, Delivery_Risk_Score__c
    FROM Order
    WHERE PoNumber LIKE 'PO-2026-%' AND Delivery_Risk_Score__c >= 70
    ORDER BY Delivery_Risk_Score__c DESC
];
System.debug('--- 위험 Order (≥70점) ' + highRisk.size() + '건 ---');
for (Order o : highRisk) {
    System.debug('  ' + o.Name + ' / PO=' + o.PoNumber + ' / ' + o.Production_Status__c +
                 ' / 점수=' + o.Delivery_Risk_Score__c);
}

System.debug('=== 검증 완료 ===');
