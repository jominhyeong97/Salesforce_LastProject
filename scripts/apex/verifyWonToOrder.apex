/*
 * Won_To_Order E2E 검증 — Quote 수락 + Opp StageName='수주' 만으로
 *                         Order + OrderItem 이 자동으로 생기는지 확인.
 *
 * 실행: sf apex run --file scripts/apex/verifyWonToOrder.apex --target-org My_Org
 */

System.debug('=== Won_To_Order E2E 검증 ===');

// 1. 임시 시드
Account acc = [SELECT Id FROM Account LIMIT 1];
Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :stdPb.Id AND IsActive = true LIMIT 1];

Opportunity opp = new Opportunity(
    Name = 'Won E2E Opp ' + System.now().getTime(),
    AccountId = acc.Id,
    StageName = '협상',
    CloseDate = Date.today().addDays(30),
    Pricebook2Id = stdPb.Id
);
insert opp;
System.debug('Opp 생성: ' + opp.Id + ' (StageName=협상)');

Quote q = new Quote(
    Name = 'Q-WonE2E', OpportunityId = opp.Id,
    Pricebook2Id = stdPb.Id, Status = '수락'
);
insert q;

insert new List<QuoteLineItem>{
    new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
                      Quantity = 8, UnitPrice = 1200),
    new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
                      Quantity = 3, UnitPrice = 4500, Discount_Amount__c = 1500)
};
System.debug('Quote+라인 2건 준비 (Status=수락)');

// 2. ★ Opp.StageName='수주' 전환 — 이게 전부
opp.StageName = '수주';
update opp;
System.debug('Opp.StageName → 수주 update 완료');

// 3. Order + OrderItem 자동 생성 확인
List<Order> autoOrders = [
    SELECT Id, Name, PoNumber, Production_Status__c, Status,
           (SELECT Id, Quantity, UnitPrice, PricebookEntry.Product2.Name FROM OrderItems)
    FROM Order WHERE Opportunity__c = :opp.Id
];

System.debug('--- 자동 생성 결과 ---');
System.debug('Order 수: ' + autoOrders.size() + ' (기대 1)');

if (autoOrders.size() == 1) {
    Order o = autoOrders[0];
    System.debug('  Order Name: ' + o.Name);
    System.debug('  PoNumber: ' + o.PoNumber);
    System.debug('  Production_Status: ' + o.Production_Status__c);
    System.debug('  OrderItem 수: ' + o.OrderItems.size() + ' (기대 2)');
    for (OrderItem oi : o.OrderItems) {
        System.debug('    Qty=' + oi.Quantity + ' UnitPrice=' + oi.UnitPrice +
                     ' Total=' + (oi.Quantity * oi.UnitPrice));
    }

    if (o.OrderItems.size() == 2) {
        System.debug('✅ 완전 자동 — Quote 수락 + Won 만으로 Order + OrderItem 모두 생성');
        System.debug('   Quote 라인 1: Qty=8, UnitPrice=1200 → effective 1200 (할인 없음)');
        System.debug('   Quote 라인 2: Qty=3, UnitPrice=4500, 할인 1500/3=500 → effective 4000');
    } else {
        System.debug('❌ OrderItem 미복사 — Case A 트리거 점검 필요');
    }
} else {
    System.debug('❌ Order 자동 생성 실패 — Won_To_Order 트리거 점검 필요');
}

System.debug('=== 검증 완료 ===');
