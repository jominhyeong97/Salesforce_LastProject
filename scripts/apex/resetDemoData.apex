// scripts/apex/resetDemoData.apex
// Sales Cockpit — 시연용 데이터 리셋 (2026-05-14 발표 대비)
//
// 1) 기존 Lead / Opp / Quote / Order / Account / Contact / Product 전부 삭제
// 2) 14일 ±기준으로 의미 있는 분포 재시드:
//      Account 10 · Contact 20 · Product 15 · Lead 8 · Opp 10 · Quote 8 · Order 15
//    홈 5카드 + Pipeline 모두 채움. 골든 시연 체인 1세트 포함.
//
// 실행: sf apex run --file scripts/apex/resetDemoData.apex --target-org My_Org

System.debug('=== RESET DEMO DATA START ===');

final Date TODAY = Date.today();   // 2026-05-12 가정
final String TAG = 'SEED-DEMO';
Savepoint sp = Database.setSavepoint();

try {

/* ============================================================
   STAGE 1 — WIPE (자식 → 부모 순)
   ============================================================ */
System.debug('--- WIPE ---');
delete [SELECT Id FROM QuoteLineItem];
delete [SELECT Id FROM Quote];
delete [SELECT Id FROM OpportunityLineItem];
delete [SELECT Id FROM Opportunity];
delete [SELECT Id FROM Lead];
delete [SELECT Id FROM Payment__c];
delete [SELECT Id FROM OrderItem];
delete [SELECT Id FROM Order];
// Service Cloud 샘플 Entitlement / Case (있으면 Account 삭제 막음)
try { delete [SELECT Id FROM Entitlement]; } catch (Exception ignore) {}
try { delete [SELECT Id FROM Case];        } catch (Exception ignore) {}
delete [SELECT Id FROM Contact];
// Account — 잔여 표준 의존성 (Sample Asset 등) 있을 수 있어 partial 허용
Database.delete([SELECT Id FROM Account], false);
// PricebookEntry 는 Product2 삭제 전 정리 (표준 Pricebook 의 PBE 만)
delete [SELECT Id FROM PricebookEntry WHERE Pricebook2.IsStandard = true AND Product2Id != null];
delete [SELECT Id FROM Product2];
System.debug('WIPE 완료');


/* ============================================================
   STAGE 2 — Pricebook 활성화
   ============================================================ */
Pricebook2 stdPb = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1];
if (!stdPb.IsActive) { stdPb.IsActive = true; update stdPb; }


/* ============================================================
   STAGE 3 — Product2 15 + PricebookEntry 15
   ============================================================ */
List<String> cats = new List<String>{'베어링', '단조품', '정밀가공품', '주물품', '판금품'};
List<Product2> products = new List<Product2>();
for (Integer i = 0; i < 15; i++) {
    String cat = cats[Math.mod(i, 5)];
    products.add(new Product2(
        Name = cat + '-' + String.valueOf(1000 + i),
        ProductCode = TAG + '-SKU-' + String.valueOf(1000 + i),
        Family = cat,
        IsActive = true,
        Description = TAG
    ));
}
insert products;

List<PricebookEntry> pbes = new List<PricebookEntry>();
for (Integer i = 0; i < products.size(); i++) {
    pbes.add(new PricebookEntry(
        Pricebook2Id = stdPb.Id,
        Product2Id = products[i].Id,
        UnitPrice = 50000 + Math.mod(i, 10) * 13000,    // 5만 ~ 16.7만
        IsActive = true
    ));
}
insert pbes;
System.debug('Product/PBE: ' + products.size());


/* ============================================================
   STAGE 4 — Account 10 (한국 회사명 + 유효 사업자번호)
   ============================================================ */
List<String> companyNames = new List<String>{
    '대성기공', '한울정밀', '우리메탈', '신화단조', '동방베어링',
    '광명MES', '태양산업', '진성정밀', '미래공업', '서울특수강'
};
List<String> ceoNames = new List<String>{
    '김영호', '박준식', '이상민', '정태경', '최민준',
    '강주원', '윤성호', '장재훈', '조현우', '한지수'
};
// AccountTriggerHandler 와 동일 가중치 (체크섬 통과)
List<Integer> WEIGHTS = new List<Integer>{1, 3, 7, 1, 3, 7, 1, 3, 5};

List<Account> accounts = new List<Account>();
for (Integer i = 0; i < 10; i++) {
    String base = String.valueOf(100000000 + i * 7919);
    Integer sumValue = 0;
    for (Integer j = 0; j < 9; j++) {
        sumValue += Integer.valueOf(base.substring(j, j + 1)) * WEIGHTS[j];
    }
    sumValue += (Integer.valueOf(base.substring(8, 9)) * 5) / 10;
    Integer chk = Math.mod(10 - Math.mod(sumValue, 10), 10);
    String bn = base + String.valueOf(chk);

    accounts.add(new Account(
        Name = companyNames[i] + '(주)',
        AccountNumber = TAG + '-' + String.valueOf(100 + i).substring(1),
        Business_Number__c = bn,
        CEO_Name__c = ceoNames[i],
        Credit_Limit__c = 50000000 + Math.mod(i, 5) * 30000000, // 5천만 ~ 1.7억
        External_Credit_Score__c = 650 + Math.mod(i * 17, 280), // 650 ~ 929
        Industry = 'Manufacturing',
        Phone = '02-' + String.valueOf(1000 + i) + '-' + String.valueOf(2000 + i * 7),
        Description = TAG
    ));
}
insert accounts;
System.debug('Account: ' + accounts.size());


/* ============================================================
   STAGE 5 — Contact 20 (Account 당 2명, 구매팀/자재팀)
   ============================================================ */
List<String> firstNames = new List<String>{'민수', '지훈', '서연', '현우', '예은', '지민', '도윤', '하윤', '주원', '시우'};
List<String> lastNames  = new List<String>{'김', '이', '박', '정', '최', '강', '조', '윤', '장', '임'};
List<String> titles     = new List<String>{'사원', '대리', '과장', '차장', '부장', '이사'};
List<String> depts      = new List<String>{'구매팀', '자재팀', '기술팀', '품질팀'};

List<Contact> contacts = new List<Contact>();
for (Integer i = 0; i < accounts.size(); i++) {
    Account a = accounts[i];
    for (Integer k = 0; k < 2; k++) {
        Integer idx = i * 2 + k;
        String tt = titles[Math.mod(idx, titles.size())];
        String dp = depts[Math.mod(idx, depts.size())];
        contacts.add(new Contact(
            AccountId = a.Id,
            FirstName = firstNames[Math.mod(idx, firstNames.size())],
            LastName  = lastNames[Math.mod(idx, lastNames.size())],
            Email     = 'buyer' + idx + '@seed-demo.example',
            Phone     = '010-' + String.valueOf(3000 + idx) + '-' + String.valueOf(1000 + idx * 17),
            Title = tt, Department = dp,
            Korean_Title__c = tt, Korean_Department__c = dp,
            Description = TAG
        ));
    }
}
insert contacts;
System.debug('Contact: ' + contacts.size());


/* ============================================================
   STAGE 6 — Lead 8 (분포: newRfqs 5건 + 제안대기 2건 + 미전환 1건)
   ============================================================ */
// 시연 시 직접 변환할 골든 Lead 포함
List<Lead> leads = new List<Lead>();

// 5건 — 최근 신규 (CreatedDate 자동 = today, Status='신규') · newRfqs 카드 표시
List<String> leadCompanies = new List<String>{
    '동광정밀(주)', '제일기공(주)', '한진단조(주)', '경성베어링(주)', '신영메탈(주)'
};
List<String> leadChannels = new List<String>{'PHONE', 'EMAIL', 'VISIT', 'EMAIL', 'PHONE'};
List<Integer> leadScores  = new List<Integer>{ 92, 78, 85, 68, 73 };
List<String> leadTitles   = new List<String>{
    '베어링 200 EA 견적 요청',
    '단조품 50 EA 견적 (긴급)',
    '정밀가공 100 EA 신규 RFQ',
    '판금품 30 EA 견적 문의',
    '주물품 80 EA 견적 의뢰'
};

for (Integer i = 0; i < 5; i++) {
    Lead l = new Lead(
        FirstName     = leadCompanies[i].replace('(주)', '') + '_담당',
        LastName      = lastNames[Math.mod(i+2, lastNames.size())] + (i == 0 ? '대표' : ''),
        Company       = leadCompanies[i],
        Title         = leadTitles[i],
        Email         = 'seed-d2-lead-' + i + '@example.com',
        Phone         = '02-' + (3100 + i * 11) + '-' + (4200 + i * 17),
        Status        = '신규',
        Source_Channel__c = leadChannels[i],
        LeadSource    = (leadChannels[i] == 'EMAIL' ? 'Web' : leadChannels[i] == 'PHONE' ? 'Phone Inquiry' : 'Other'),
        Lead_Score__c = leadScores[i],
        Industry      = 'Manufacturing',
        Rating        = (leadScores[i] >= 80 ? 'Hot' : leadScores[i] >= 65 ? 'Warm' : 'Cold'),
        Description   = TAG + ' — 신규 RFQ',
        RFQ_Spec_JSON__c = '{"items":[{"sku":"' + cats[Math.mod(i,5)] + '-1000","qty":' + (50 + i*30) + '}],"note":"' + leadTitles[i] + '"}'
    );
    leads.add(l);
}

// 2건 — 제안대기 (priorityLeads 카드)
leads.add(new Lead(
    FirstName='박', LastName='차장', Company='청호정밀(주)', Title='베어링 추가 견적',
    Email='seed-d2-lead-5@example.com', Phone='02-3155-4255',
    Status='제안대기', Source_Channel__c='EMAIL', LeadSource='Web',
    Lead_Score__c=88, Industry='Manufacturing', Rating='Hot',
    Description=TAG + ' — 제안대기'
));
leads.add(new Lead(
    FirstName='이', LastName='과장', Company='경동기계(주)', Title='판금 견적 follow-up',
    Email='seed-d2-lead-6@example.com', Phone='02-3166-4266',
    Status='제안대기', Source_Channel__c='PHONE', LeadSource='Phone Inquiry',
    Lead_Score__c=72, Industry='Manufacturing', Rating='Warm',
    Description=TAG + ' — 제안대기'
));

// 1건 — 미전환 (history record)
leads.add(new Lead(
    FirstName='최', LastName='부장', Company='삼성공업(주)', Title='취소된 RFQ',
    Email='seed-d2-lead-7@example.com', Phone='02-3177-4277',
    Status='미전환', Source_Channel__c='VISIT', LeadSource='Other',
    Lead_Score__c=45, Industry='Manufacturing', Rating='Cold',
    Description=TAG + ' — 미전환 (예산 미확보)'
));

insert leads;
System.debug('Lead: ' + leads.size());


/* ============================================================
   STAGE 7 — Opportunity 10 (Stage 분포: 발굴2 / 견적작성2 / 견적발송2 / 협상2 / 수주2)
   ============================================================ */
List<Opportunity> opps = new List<Opportunity>();

// 발굴 2건 (10%)
opps.add(new Opportunity(
    Name='대성기공 1차 RFQ 발굴', AccountId=accounts[0].Id, StageName='발굴',
    CloseDate=TODAY.addDays(45), Amount=12500000,
    Promised_Delivery_Date__c=TODAY.addDays(60),
    Pricebook2Id=stdPb.Id, LeadSource='Web',
    Description=TAG + ' — 발굴 단계'
));
opps.add(new Opportunity(
    Name='한울정밀 베어링 신규', AccountId=accounts[1].Id, StageName='발굴',
    CloseDate=TODAY.addDays(40), Amount=8400000,
    Promised_Delivery_Date__c=TODAY.addDays(55),
    Pricebook2Id=stdPb.Id, LeadSource='Phone Inquiry',
    Description=TAG + ' — 발굴 단계'
));

// 견적 작성 2건 (30%)
opps.add(new Opportunity(
    Name='우리메탈 단조 100EA', AccountId=accounts[2].Id, StageName='견적 작성',
    CloseDate=TODAY.addDays(30), Amount=21500000,
    Promised_Delivery_Date__c=TODAY.addDays(45),
    Pricebook2Id=stdPb.Id, LeadSource='Web',
    Description=TAG + ' — 견적 작성 중'
));
opps.add(new Opportunity(
    Name='신화단조 정밀가공 견적', AccountId=accounts[3].Id, StageName='견적 작성',
    CloseDate=TODAY.addDays(28), Amount=18700000,
    Promised_Delivery_Date__c=TODAY.addDays(42),
    Pricebook2Id=stdPb.Id, LeadSource='Other',
    Description=TAG + ' — 견적 작성 중'
));

// 견적 발송 2건 (60%)
opps.add(new Opportunity(
    Name='동방베어링 양산 견적', AccountId=accounts[4].Id, StageName='견적 발송',
    CloseDate=TODAY.addDays(20), Amount=33200000,
    Promised_Delivery_Date__c=TODAY.addDays(35),
    Pricebook2Id=stdPb.Id, LeadSource='Web',
    Description=TAG + ' — 견적 발송, 응답 대기'
));
opps.add(new Opportunity(
    Name='광명MES 판금 시제품', AccountId=accounts[5].Id, StageName='견적 발송',
    CloseDate=TODAY.addDays(18), Amount=9800000,
    Promised_Delivery_Date__c=TODAY.addDays(30),
    Pricebook2Id=stdPb.Id, LeadSource='Phone Inquiry',
    Description=TAG + ' — 견적 발송, 열람됨'
));

// 협상 2건 (80%)
opps.add(new Opportunity(
    Name='태양산업 주물 양산', AccountId=accounts[6].Id, StageName='협상',
    CloseDate=TODAY.addDays(12), Amount=45000000,
    Promised_Delivery_Date__c=TODAY.addDays(28),
    Pricebook2Id=stdPb.Id, LeadSource='Other',
    Description=TAG + ' — 가격 조정 중'
));
opps.add(new Opportunity(
    Name='진성정밀 정밀가공 follow', AccountId=accounts[7].Id, StageName='협상',
    CloseDate=TODAY.addDays(10), Amount=27500000,
    Promised_Delivery_Date__c=TODAY.addDays(25),
    Pricebook2Id=stdPb.Id, LeadSource='Web',
    Description=TAG + ' — 5% 인하 협상'
));

// 수주 2건 (100% Won)
opps.add(new Opportunity(
    Name='미래공업 베어링 1차 수주', AccountId=accounts[8].Id, StageName='수주',
    CloseDate=TODAY.addDays(-3), Amount=22000000,
    Promised_Delivery_Date__c=TODAY.addDays(18),
    Pricebook2Id=stdPb.Id, LeadSource='Web',
    Description=TAG + ' — 수주 완료'
));
opps.add(new Opportunity(
    Name='서울특수강 단조 수주', AccountId=accounts[9].Id, StageName='수주',
    CloseDate=TODAY.addDays(-1), Amount=18500000,
    Promised_Delivery_Date__c=TODAY.addDays(22),
    Pricebook2Id=stdPb.Id, LeadSource='Other',
    Description=TAG + ' — 수주 완료'
));

insert opps;
System.debug('Opportunity: ' + opps.size());


/* ============================================================
   STAGE 8 — Quote 8 + QuoteLineItem ~16
   (sentQuotes 카드용 발송/응답대기 5건 + 초안/수락/거절 분포)
   ============================================================ */
// (Quote 는 견적 작성 이상 Opp 에 연결)
List<Quote> quotes = new List<Quote>();

// 초안 1건 (Opp 견적 작성)
quotes.add(new Quote(
    Name='Q-DEMO-001-우리메탈', OpportunityId=opps[2].Id, Pricebook2Id=stdPb.Id,
    Status='초안', ExpirationDate=TODAY.addDays(30),
    AE_Edit_Count__c=3, AI_Draft_Confidence__c=0.78,
    Description=TAG + ' — AE 편집 중'
));

// 발송 3건 (sentQuotes 카드, Sent_Date 최근 1~5일)
quotes.add(new Quote(
    Name='Q-DEMO-002-신화단조', OpportunityId=opps[3].Id, Pricebook2Id=stdPb.Id,
    Status='발송', ExpirationDate=TODAY.addDays(25),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-1), Time.newInstance(10,0,0,0)),
    AE_Edit_Count__c=5, AI_Draft_Confidence__c=0.85,
    Description=TAG + ' — 어제 발송'
));
quotes.add(new Quote(
    Name='Q-DEMO-003-동방베어링', OpportunityId=opps[4].Id, Pricebook2Id=stdPb.Id,
    Status='발송', ExpirationDate=TODAY.addDays(20),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-3), Time.newInstance(14,30,0,0)),
    Last_Opened_At__c=DateTime.newInstance(TODAY.addDays(-2), Time.newInstance(9,15,0,0)),
    AE_Edit_Count__c=7, AI_Draft_Confidence__c=0.91,
    Description=TAG + ' — 발송 후 열람'
));
quotes.add(new Quote(
    Name='Q-DEMO-004-광명MES', OpportunityId=opps[5].Id, Pricebook2Id=stdPb.Id,
    Status='발송', ExpirationDate=TODAY.addDays(18),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-5), Time.newInstance(11,0,0,0)),
    Last_Opened_At__c=DateTime.newInstance(TODAY.addDays(-4), Time.newInstance(16,20,0,0)),
    Last_Clicked_At__c=DateTime.newInstance(TODAY.addDays(-4), Time.newInstance(16,22,0,0)),
    AE_Edit_Count__c=4, AI_Draft_Confidence__c=0.82,
    Description=TAG + ' — 발송, 링크 클릭됨'
));

// 응답대기 2건
quotes.add(new Quote(
    Name='Q-DEMO-005-태양산업', OpportunityId=opps[6].Id, Pricebook2Id=stdPb.Id,
    Status='응답대기', ExpirationDate=TODAY.addDays(12),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-7), Time.newInstance(9,30,0,0)),
    Last_Opened_At__c=DateTime.newInstance(TODAY.addDays(-6), Time.newInstance(10,45,0,0)),
    AE_Edit_Count__c=6, AI_Draft_Confidence__c=0.88,
    Description=TAG + ' — 고객 응답 대기'
));
quotes.add(new Quote(
    Name='Q-DEMO-006-진성정밀', OpportunityId=opps[7].Id, Pricebook2Id=stdPb.Id,
    Status='응답대기', ExpirationDate=TODAY.addDays(10),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-9), Time.newInstance(13,0,0,0)),
    Last_Opened_At__c=DateTime.newInstance(TODAY.addDays(-8), Time.newInstance(15,30,0,0)),
    AE_Edit_Count__c=8, AI_Draft_Confidence__c=0.93,
    Description=TAG + ' — 재견적 요청 가능성'
));

// 수락 1건 (수주 Opp 연결, 골든 체인)
quotes.add(new Quote(
    Name='Q-DEMO-007-미래공업', OpportunityId=opps[8].Id, Pricebook2Id=stdPb.Id,
    Status='수락', ExpirationDate=TODAY.addDays(15),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-10), Time.newInstance(10,0,0,0)),
    Last_Opened_At__c=DateTime.newInstance(TODAY.addDays(-9), Time.newInstance(11,0,0,0)),
    AE_Edit_Count__c=5, AI_Draft_Confidence__c=0.90,
    Description=TAG + ' — 수락 완료 → Order 자동 생성'
));

// 거절 1건
quotes.add(new Quote(
    Name='Q-DEMO-008-서울특수강', OpportunityId=opps[9].Id, Pricebook2Id=stdPb.Id,
    Status='거절', ExpirationDate=TODAY.addDays(-5),
    Sent_Date__c=DateTime.newInstance(TODAY.addDays(-14), Time.newInstance(9,0,0,0)),
    Last_Opened_At__c=DateTime.newInstance(TODAY.addDays(-13), Time.newInstance(10,0,0,0)),
    AE_Edit_Count__c=10, AI_Draft_Confidence__c=0.75,
    Description=TAG + ' — 예산 초과로 거절'
));

insert quotes;

// QuoteLineItem 각 Quote 당 2건
List<QuoteLineItem> qlis = new List<QuoteLineItem>();
for (Integer i = 0; i < quotes.size(); i++) {
    PricebookEntry p1 = pbes[Math.mod(i * 2,     pbes.size())];
    PricebookEntry p2 = pbes[Math.mod(i * 2 + 1, pbes.size())];
    Integer q1 = 50 + Math.mod(i * 17, 100);  // 50~149
    Integer q2 = 20 + Math.mod(i * 13, 50);   // 20~69
    qlis.add(new QuoteLineItem(
        QuoteId=quotes[i].Id, PricebookEntryId=p1.Id, Product2Id=p1.Product2Id,
        Quantity=q1, UnitPrice=p1.UnitPrice, Discount_Amount__c=0
    ));
    qlis.add(new QuoteLineItem(
        QuoteId=quotes[i].Id, PricebookEntryId=p2.Id, Product2Id=p2.Product2Id,
        Quantity=q2, UnitPrice=p2.UnitPrice,
        Discount_Amount__c=(Math.mod(i, 2) == 0 ? 50000 : 0)
    ));
}
insert qlis;
System.debug('Quote: ' + quotes.size() + ' / QLI: ' + qlis.size());


/* ============================================================
   STAGE 9 — Order 15
   분포: 위험 3 / 대형지연 2 / 정시 완료 6 / 장기미수 4
   ============================================================ */
List<Order> orders = new List<Order>();
Map<Integer, Decimal> orderTotals = new Map<Integer, Decimal>(); // index → total

for (Integer i = 0; i < 15; i++) {
    Account acc = accounts[Math.mod(i, accounts.size())];
    String poEnd;  Date effDate;  Date endDate;  String prodStatus;
    Integer riskScore;

    if (i < 3) {
        // 위험 3건: D+3~7 지연 위험
        poEnd = '6'; effDate = TODAY.addDays(-7);
        endDate = TODAY.addDays(3 + i);   // D-3, D-4, D-5
        prodStatus = 'InProgress';
        riskScore = 75 + i * 5;            // 75, 80, 85
    } else if (i < 5) {
        // 대형지연 2건: 이미 초과
        poEnd = '9'; effDate = TODAY.addDays(-60);
        endDate = TODAY.addDays(-10 - i);  // D+13, D+14 초과
        prodStatus = 'InProgress';
        riskScore = 92 + i;                // 95, 96
    } else if (i < 11) {
        // 정시 완료 6건 (분할 입금)
        poEnd = String.valueOf(Math.mod(i, 6));
        effDate = TODAY.addDays(-(30 + i * 10));
        endDate = TODAY.addDays(-(15 + i * 5));
        prodStatus = (Math.mod(i, 2) == 0) ? 'Done' : 'Shipped';
        riskScore = 10 + Math.mod(i, 30);
    } else {
        // 장기미수 4건
        poEnd = String.valueOf(Math.mod(i, 6));
        effDate = TODAY.addDays(-(180 + (i - 11) * 15));
        endDate = TODAY.addDays(-(160 + (i - 11) * 15));
        prodStatus = 'Shipped';
        riskScore = 20 + Math.mod(i, 30);
    }

    String poNumber = 'PO-2026-' + String.valueOf(100 + i).substring(1) + poEnd;

    orders.add(new Order(
        AccountId          = acc.Id,
        Name               = 'ORD-' + String.valueOf(1000 + i),
        EffectiveDate      = effDate,
        EndDate            = endDate,
        Status             = 'Draft',
        Pricebook2Id       = stdPb.Id,
        PoNumber           = poNumber,
        Production_Status__c       = prodStatus,
        Delivery_Risk_Score__c     = riskScore,
        Last_ErpSync_At__c         = DateTime.now().addHours(-Math.mod(i, 12)),
        ERP_Expected_Ship_Date__c  = endDate.addDays(riskScore >= 70 ? 5 : 0),
        Description = TAG
    ));
}

// 골든 체인 Order — 수주 Opp(opps[8]) 연결, 시연용 reference
orders.add(new Order(
    AccountId          = accounts[8].Id,
    Opportunity__c     = opps[8].Id,
    Name               = 'ORD-GOLDEN-DEMO',
    EffectiveDate      = TODAY.addDays(-2),
    EndDate            = opps[8].Promised_Delivery_Date__c,
    Status             = 'Draft',
    Pricebook2Id       = stdPb.Id,
    PoNumber           = 'PO-2026-GOLDEN',
    Production_Status__c       = 'InProgress',
    Delivery_Risk_Score__c     = 35,
    Last_ErpSync_At__c         = DateTime.now().addMinutes(-30),
    ERP_Expected_Ship_Date__c  = opps[8].Promised_Delivery_Date__c,
    Description = TAG + ' — 골든 체인 (수주→Order 자동 생성 시연)'
));

insert orders;
System.debug('Order: ' + orders.size());


/* ============================================================
   STAGE 10 — OrderItem (각 Order 2건, Total 계산)
   ============================================================ */
List<OrderItem> items = new List<OrderItem>();
Map<Id, Decimal> orderTotalsById = new Map<Id, Decimal>();

for (Integer i = 0; i < orders.size(); i++) {
    PricebookEntry p1 = pbes[Math.mod(i,     pbes.size())];
    PricebookEntry p2 = pbes[Math.mod(i + 5, pbes.size())];
    Integer q1 = 30 + Math.mod(i * 11, 50);  // 30~79
    Integer q2 = 15 + Math.mod(i * 7,  35);  // 15~49
    Decimal total = (q1 * p1.UnitPrice) + (q2 * p2.UnitPrice);
    orderTotalsById.put(orders[i].Id, total);

    items.add(new OrderItem(
        OrderId=orders[i].Id, PricebookEntryId=p1.Id, Quantity=q1, UnitPrice=p1.UnitPrice
    ));
    items.add(new OrderItem(
        OrderId=orders[i].Id, PricebookEntryId=p2.Id, Quantity=q2, UnitPrice=p2.UnitPrice
    ));
}
insert items;
System.debug('OrderItem: ' + items.size());


/* ============================================================
   STAGE 11 — Payment__c (정시 완납 + 장기미수 부분입금)
   ============================================================ */
List<Payment__c> payments = new List<Payment__c>();
List<Order> ordersToUpdate = new List<Order>();
Map<Id, Decimal> accountOutstanding = new Map<Id, Decimal>();  // AR 합산용

for (Integer i = 0; i < orders.size(); i++) {
    Order o = orders[i];
    Decimal total = orderTotalsById.get(o.Id);
    Decimal paid = 0;

    if (i < 5) {
        // 위험·대형지연 — 입금 0 (생산중)
    } else if (i < 11) {
        // 정시 완납 — 3회 분할 (전액 회수)
        Decimal third = (total / 3).setScale(0);
        for (Integer k = 0; k < 3; k++) {
            Decimal amt = (k == 2) ? (total - paid) : third;
            payments.add(new Payment__c(
                Order__c=o.Id, Paid_Amount__c=amt,
                Paid_Date__c=o.EffectiveDate.addDays(10 + k * 14),
                Status__c='Paid',
                Memo__c=TAG + ' 분할 ' + (k + 1) + '/3'
            ));
            paid += amt;
        }
    } else if (i < 15) {
        // 장기미수 — 1/3 만 부분입금, 잔액 outstanding
        Decimal amt = (total / 3).setScale(0);
        payments.add(new Payment__c(
            Order__c=o.Id, Paid_Amount__c=amt,
            Paid_Date__c=o.EffectiveDate.addDays(20),
            Status__c='Paid',
            Memo__c=TAG + ' 부분입금 (잔액 미수)'
        ));
        paid = amt;
        // 잔액을 Account 미수금에 합산
        Decimal outstanding = total - paid;
        Decimal cur = accountOutstanding.containsKey(o.AccountId) ? accountOutstanding.get(o.AccountId) : 0;
        accountOutstanding.put(o.AccountId, cur + outstanding);
    } else {
        // 골든 체인 — 1차 입금 (50%) 진행 중
        Decimal amt = (total / 2).setScale(0);
        payments.add(new Payment__c(
            Order__c=o.Id, Paid_Amount__c=amt,
            Paid_Date__c=TODAY.addDays(-1),
            Status__c='Paid',
            Memo__c=TAG + ' 1차 입금 (50%)'
        ));
        paid = amt;
    }

    if (paid > 0) {
        ordersToUpdate.add(new Order(Id=o.Id, Total_Paid_Amount__c=paid));
    }
}
insert payments;
if (!ordersToUpdate.isEmpty()) update ordersToUpdate;
System.debug('Payment__c: ' + payments.size() + ' / Order paid-update: ' + ordersToUpdate.size());


/* ============================================================
   STAGE 12 — Account Total_AR / Long_Term_Debtor 직접 set
   (장기미수 Order 가 연결된 Account 4건)
   ============================================================ */
List<Account> accUpdates = new List<Account>();
for (Account a : [SELECT Id FROM Account]) {
    if (accountOutstanding.containsKey(a.Id)) {
        accUpdates.add(new Account(
            Id=a.Id,
            Total_AR__c = accountOutstanding.get(a.Id),
            Long_Term_Debtor__c = true
        ));
    }
}
if (!accUpdates.isEmpty()) update accUpdates;
System.debug('Account AR update: ' + accUpdates.size());


/* ============================================================
   STAGE 13 — 검증 카운트
   ============================================================ */
System.debug('--------- SEED RESULT ---------');
System.debug('Account     : ' + [SELECT COUNT() FROM Account]);
System.debug('Contact     : ' + [SELECT COUNT() FROM Contact]);
System.debug('Product2    : ' + [SELECT COUNT() FROM Product2]);
System.debug('Lead        : ' + [SELECT COUNT() FROM Lead]);
System.debug('Opportunity : ' + [SELECT COUNT() FROM Opportunity]);
System.debug('Quote       : ' + [SELECT COUNT() FROM Quote]);
System.debug('QuoteLineItem : ' + [SELECT COUNT() FROM QuoteLineItem]);
System.debug('Order       : ' + [SELECT COUNT() FROM Order]);
System.debug('OrderItem   : ' + [SELECT COUNT() FROM OrderItem]);
System.debug('Payment__c  : ' + [SELECT COUNT() FROM Payment__c]);

System.debug('--- 홈 5카드 미리보기 ---');
System.debug('newRfqs (Lead 신규 7일): '       + [SELECT COUNT() FROM Lead WHERE Status='신규' AND IsConverted=false AND CreatedDate >= LAST_N_DAYS:7]);
System.debug('priorityLeads (신규+제안대기): ' + [SELECT COUNT() FROM Lead WHERE Status IN ('신규','제안대기') AND IsConverted=false AND Lead_Score__c != null]);
System.debug('sentQuotes (발송+응답대기): '   + [SELECT COUNT() FROM Quote WHERE Status IN ('발송','응답대기')]);
System.debug('riskyOrders (Risk≥70): '         + [SELECT COUNT() FROM Order WHERE Delivery_Risk_Score__c >= 70]);
System.debug('arActions (장기미수 OR AR≥5M): ' + [SELECT COUNT() FROM Account WHERE Long_Term_Debtor__c=true OR Total_AR__c >= 5000000]);

System.debug('=== RESET DEMO DATA DONE ===');

} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '!! FAILED — rolled back: ' + e.getTypeName() + ' : ' + e.getMessage());
    System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    throw e;
}
