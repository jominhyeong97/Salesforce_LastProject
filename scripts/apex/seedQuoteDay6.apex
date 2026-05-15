// Day 6 Phase A 시연용 Quote 시드 1건 생성
// - 시드 Account 1건 + 그 Account의 Opportunity에 Pricebook 연결
// - Quote 1건 (Status=초안) + QuoteLineItem 2건 (할인 0 / 할인 20000)
// 멱등성: Q-DAY6-001 이름이 이미 있으면 새로 안 만듦

Pricebook2 std = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];

List<Quote> existing = [SELECT Id FROM Quote WHERE Name = 'Q-DAY6-001' LIMIT 1];
if (!existing.isEmpty()) {
    System.debug('Quote already exists: ' + existing[0].Id);
    return;
}

// 시드 Account (D2 시드 또는 임의의 Account)
List<Account> accs = [SELECT Id FROM Account WHERE Business_Number__c != null LIMIT 1];
if (accs.isEmpty()) accs = [SELECT Id FROM Account LIMIT 1];
if (accs.isEmpty()) throw new System.IllegalArgumentException('Account 없음 — 시드 먼저 실행 필요');
Account acc = accs[0];

// Opportunity (없으면 생성)
List<Opportunity> opps = [
    SELECT Id, Pricebook2Id FROM Opportunity
    WHERE AccountId = :acc.Id LIMIT 1
];
Opportunity opp;
if (opps.isEmpty()) {
    opp = new Opportunity(
        Name = 'Day6 견적 시연',
        AccountId = acc.Id,
        StageName = '견적 작성',
        CloseDate = Date.today().addDays(30),
        Pricebook2Id = std.Id
    );
    insert opp;
} else {
    opp = opps[0];
    if (opp.Pricebook2Id == null) {
        opp.Pricebook2Id = std.Id;
        update opp;
    }
}

// Quote 1건
Quote q = new Quote(
    Name = 'Q-DAY6-001',
    OpportunityId = opp.Id,
    Pricebook2Id = std.Id,
    Status = '초안',
    ExpirationDate = Date.today().addDays(14)
);
insert q;

// 시드 Product 2~3건 PricebookEntry
List<PricebookEntry> pbes = [
    SELECT Id, Product2Id, UnitPrice, Product2.Name
    FROM PricebookEntry
    WHERE Pricebook2Id = :std.Id AND IsActive = true AND Product2.IsActive = true
    LIMIT 3
];
if (pbes.size() < 2) throw new System.IllegalArgumentException('Product/PricebookEntry 부족 — 시드 먼저 실행 필요');

List<QuoteLineItem> qlis = new List<QuoteLineItem>{
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbes[0].Id,
        Product2Id       = pbes[0].Product2Id,
        Quantity         = 100,
        UnitPrice        = pbes[0].UnitPrice,
        Discount_Amount__c = 0
    ),
    new QuoteLineItem(
        QuoteId          = q.Id,
        PricebookEntryId = pbes[1].Id,
        Product2Id       = pbes[1].Product2Id,
        Quantity         = 10,
        UnitPrice        = pbes[1].UnitPrice,
        Discount_Amount__c = 20000
    )
};
insert qlis;

System.debug('✅ Quote Created: ' + q.Id);
System.debug('   Account: ' + acc.Id);
System.debug('   Opp: ' + opp.Id);
System.debug('   Lines: ' + qlis.size());
System.debug('   URL: https://orgfarm-25f6d831e2-dev-ed.develop.my.salesforce.com/' + q.Id);
