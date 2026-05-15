/*
 * Case A 검증 — 수락된 Quote 가 있는 Opp 에 신규 Order 인서트 시
 *               OrderItem 이 자동 복사되는지 확인.
 *
 * 실행: sf apex run --file scripts/apex/verifyCaseA.apex --target-org My_Org
 */

System.debug('=== Case A 검증 (Quote 라인 → OrderItem 자동 복사) ===');

// 1. 수락된 Quote + 라인 있는 Opp 1건 찾기 (없으면 시드에서 임시 생성)
List<Quote> acceptedQuotes = [
    SELECT Id, Name, OpportunityId, Opportunity.Name, Opportunity.AccountId, Opportunity.Pricebook2Id,
           (SELECT Id FROM QuoteLineItems)
    FROM Quote
    WHERE Status = '수락'
    LIMIT 5
];

Quote target;
for (Quote q : acceptedQuotes) {
    if (q.QuoteLineItems != null && !q.QuoteLineItems.isEmpty() && q.OpportunityId != null) {
        target = q;
        break;
    }
}

if (target == null) {
    System.debug('⚠️ Status=수락 + 라인 있는 Quote 없음. 임시 데이터로 검증.');

    // 임시 시드
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
    Id stdPb = pb.Id;
    PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :stdPb AND IsActive = true LIMIT 1];

    Opportunity tmpOpp = new Opportunity(
        Name = 'CaseA Verify Opp ' + System.now().getTime(),
        AccountId = acc.Id,
        StageName = '발굴',
        CloseDate = Date.today().addDays(30),
        Pricebook2Id = stdPb
    );
    insert tmpOpp;

    Quote tmpQ = new Quote(
        Name = 'CaseA Verify Quote', OpportunityId = tmpOpp.Id,
        Pricebook2Id = stdPb, Status = '수락'
    );
    insert tmpQ;

    insert new List<QuoteLineItem>{
        new QuoteLineItem(QuoteId = tmpQ.Id, PricebookEntryId = pbe.Id,
                          Quantity = 10, UnitPrice = 1000, Discount_Amount__c = 0),
        new QuoteLineItem(QuoteId = tmpQ.Id, PricebookEntryId = pbe.Id,
                          Quantity = 5,  UnitPrice = 2000, Discount_Amount__c = 500)
    };

    target = [
        SELECT Id, Name, OpportunityId, Opportunity.Name, Opportunity.AccountId, Opportunity.Pricebook2Id,
               (SELECT Id FROM QuoteLineItems)
        FROM Quote WHERE Id = :tmpQ.Id LIMIT 1
    ];
}

System.debug('대상 Quote: ' + target.Name +
             ' (Opp=' + target.Opportunity.Name +
             ', 라인=' + target.QuoteLineItems.size() + '건)');

// 2. 신규 Order 인서트 (Won_To_Order Flow 가 만드는 것과 동일 시그니처)
//    이 Org 는 표준 Order.OpportunityId 미활성 → Opportunity__c custom lookup 사용
Order newOrder = new Order(
    AccountId      = target.Opportunity.AccountId,
    Opportunity__c = target.OpportunityId,
    EffectiveDate  = Date.today(),
    Status         = 'Draft',
    Pricebook2Id   = target.Opportunity.Pricebook2Id,
    PoNumber       = 'PO-CASEA-' + System.now().getTime()
);

System.debug('신규 Order 인서트 직전...');
insert newOrder;
System.debug('Order 생성: ' + newOrder.Id);

// 3. 트리거가 OrderItem 만들었는지 확인
List<OrderItem> copied = [
    SELECT Id, Quantity, UnitPrice, PricebookEntry.Product2.Name
    FROM OrderItem
    WHERE OrderId = :newOrder.Id
    ORDER BY Quantity DESC
];

System.debug('--- 자동 복사된 OrderItem ' + copied.size() + '건 ---');
for (OrderItem oi : copied) {
    System.debug('  ' + oi.PricebookEntry.Product2.Name +
                 ' / Qty=' + oi.Quantity +
                 ' / UnitPrice=' + oi.UnitPrice +
                 ' / Total=' + (oi.Quantity * oi.UnitPrice));
}

// 4. 결과 판정
if (copied.size() == target.QuoteLineItems.size()) {
    System.debug('✅ 검증 통과 — Quote 라인 ' + target.QuoteLineItems.size() +
                 '건 → OrderItem ' + copied.size() + '건 자동 복사 정합');
} else {
    System.debug('❌ 검증 실패 — Quote 라인 ' + target.QuoteLineItems.size() +
                 '건 ≠ OrderItem ' + copied.size() + '건');
}

System.debug('=== 검증 완료 ===');
