// E2E: DelayNotice Prompt 실 AI 호출
List<Order> orders = [
    SELECT Id, PoNumber, Account.Name, Delivery_Risk_Score__c
    FROM Order
    WHERE Delivery_Risk_Score__c >= 70
    ORDER BY Delivery_Risk_Score__c DESC
    LIMIT 1
];
if (orders.isEmpty()) {
    System.debug('위험 Order 없음 — 먼저 ERP 동기화 필요');
    return;
}
Order o = orders[0];
System.debug('대상 Order: ' + o.PoNumber + ' / ' + o.Account.Name + ' / 점수=' + o.Delivery_Risk_Score__c);

DelayNoticeService.Draft d = DelayNoticeService.draft(o.Id, '생산 라인 점검 중, 부품 입고 대기');
System.debug('aiSource=' + d.aiSource);
System.debug('subject=' + d.subject);
System.debug('body=\n' + d.body);
if (d.aiError != null) System.debug('aiError=' + d.aiError);
