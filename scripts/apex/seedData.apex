// scripts/apex/seedData.apex
// Sales Cockpit — Day 2 Seed Data (SEED-D2)
// Product2 50 + PricebookEntry 50 + Account 30(한국) + Contact 60
// + Order 100(위험 5/대형지연 5/정시 90) + OrderItem 200 + Payment__c 분할/장기미수
//
// 멱등성: 모든 레코드에 'SEED-D2' 태그(Description / Memo). cleanupSeedData.apex 로 일괄 삭제.
// 안전장치: Database.setSavepoint() — 어떤 단계라도 실패 시 전체 롤백.
//
// 실행: sf apex run --file scripts/apex/seedData.apex --target-org My_Org

System.debug('=== Sales Cockpit Seed Day 2 START ===');

final String SEED_TAG = 'SEED-D2';
final Date TODAY = Date.today();
Savepoint sp = Database.setSavepoint();

try {

    /* ========== 0. 표준 Pricebook 활성화 (DE org 기본 inactive) ========== */
    Pricebook2 stdPb = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1];
    if (!stdPb.IsActive) {
        stdPb.IsActive = true;
        update stdPb;
        System.debug('Standard Pricebook activated.');
    }

    /* ========== 1. Product2 50건 + PricebookEntry 50건 ========== */
    List<String> categories = new List<String>{
        '베어링', '단조품', '정밀가공품', '주물품', '판금품'
    };
    List<Product2> products = new List<Product2>();
    for (Integer i = 0; i < 50; i++) {
        String cat = categories[Math.mod(i, 5)];
        products.add(new Product2(
            Name = cat + '-' + String.valueOf(1000 + i),
            ProductCode = SEED_TAG + '-SKU-' + String.valueOf(1000 + i), // 필터 가능 표준 키
            Family = cat,
            IsActive = true,
            Description = SEED_TAG
        ));
    }
    insert products;

    List<PricebookEntry> pbes = new List<PricebookEntry>();
    for (Integer i = 0; i < products.size(); i++) {
        pbes.add(new PricebookEntry(
            Pricebook2Id = stdPb.Id,
            Product2Id = products[i].Id,
            UnitPrice = 50000 + Math.mod(i, 10) * 13000, // 50,000 ~ 167,000
            IsActive = true
        ));
    }
    insert pbes;
    System.debug('Product2 / PricebookEntry: ' + products.size() + ' / ' + pbes.size());

    /* ========== 2. Account 30건 (한국 회사명 + 유효 사업자번호) ========== */
    List<String> companyNames = new List<String>{
        '대성기공', '한울정밀', '우리메탈', '신화단조', '동방베어링',
        '광명MES', '태양산업', '진성정밀', '미래공업', '서울특수강',
        '한라정공', '동양철강', '청호정밀', '경동기계', '삼성공업',
        '연세금속', '대원ENG', '풍산정밀', '명문기공', '엠케이주물',
        '천일가공', '동신메탈', '한국정밀산업', '경인특수', '대륙기공',
        '청송단조', '신한공업', '제일정공', '동남메탈', '평화정밀'
    };
    List<String> ceoNames = new List<String>{
        '김영호', '박준식', '이상민', '정태경', '최민준',
        '강주원', '윤성호', '장재훈', '조현우', '한지수',
        '오세진', '서동건', '신지훈', '권혁수', '황인석',
        '안준영', '홍성민', '송태호', '문재석', '배상혁',
        '백승현', '남기훈', '심재원', '노현철', '하정우',
        '주민수', '구본혁', '유지환', '전성호', '임도현'
    };
    // AccountTriggerHandler 와 동일한 가중치(체크섬 통과해야 트리거가 addError 안 함)
    List<Integer> WEIGHTS = new List<Integer>{1, 3, 7, 1, 3, 7, 1, 3, 5};

    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 30; i++) {
        // 9자리 base + 체크섬 1자리 → 유효한 한국 사업자번호 10자리
        String base = String.valueOf(100000000 + i * 7919);
        Integer sumValue = 0;
        for (Integer j = 0; j < 9; j++) {
            sumValue += Integer.valueOf(base.substring(j, j + 1)) * WEIGHTS[j];
        }
        sumValue += (Integer.valueOf(base.substring(8, 9)) * 5) / 10; // 정수 나눗셈
        Integer check = Math.mod(10 - Math.mod(sumValue, 10), 10);
        String bn = base + String.valueOf(check); // 10자리 (트리거가 하이픈 자동 부착)

        // 시드 식별: AccountNumber 표준 텍스트(40자, 필터 가능). cleanup 키.
        String acctNum = SEED_TAG + '-' + String.valueOf(100 + i).substring(1); // SEED-D2-00 ~ SEED-D2-29
        accounts.add(new Account(
            Name = companyNames[i] + '(주)',
            AccountNumber = acctNum,
            Business_Number__c = bn,
            CEO_Name__c = ceoNames[i],
            Credit_Limit__c = 50000000 + Math.mod(i, 5) * 30000000, // 5천만 ~ 1.7억
            External_Credit_Score__c = 600 + Math.mod(i * 17, 350), // 600 ~ 949
            Industry = 'Manufacturing',
            Description = SEED_TAG
        ));
    }
    insert accounts;
    System.debug('Account: ' + accounts.size());

    /* ========== 3. Contact 60건 (Account당 2명 — 구매팀 + 자재팀) ========== */
    List<String> firstNames = new List<String>{
        '민수', '지훈', '서연', '현우', '예은',
        '지민', '도윤', '하윤', '주원', '시우',
        '하준', '서아', '지유', '예준', '아인'
    };
    List<String> lastNames = new List<String>{
        '김', '이', '박', '정', '최',
        '강', '조', '윤', '장', '임'
    };
    // Korean_Title__c / Korean_Department__c 는 restricted picklist — 정의된 값만 허용
    List<String> titles = new List<String>{
        '사원', '대리', '과장', '차장', '부장', '이사', '상무'
    };
    List<String> departments = new List<String>{
        '영업팀', '구매팀', '자재팀', '기술팀', '품질팀'
    };

    List<Contact> contacts = new List<Contact>();
    for (Integer i = 0; i < accounts.size(); i++) {
        Account a = accounts[i];
        for (Integer k = 0; k < 2; k++) {
            Integer idx = i * 2 + k;
            String tt = titles[Math.mod(idx, titles.size())];
            String dp = departments[Math.mod(idx, departments.size())];
            contacts.add(new Contact(
                AccountId = a.Id,
                FirstName = firstNames[Math.mod(idx, firstNames.size())],
                LastName = lastNames[Math.mod(idx, lastNames.size())],
                Email = 'buyer' + idx + '@seed-test.example',
                Phone = '02-' + String.valueOf(3000 + idx) + '-' + String.valueOf(1000 + idx),
                Title = tt,
                Department = dp,
                Korean_Title__c = tt,
                Korean_Department__c = dp,
                Description = SEED_TAG
            ));
        }
    }
    insert contacts;
    System.debug('Contact: ' + contacts.size());

    /* ========== 4. Order 100건 ==========
     * 분포 (PoNumber 끝자리 + Production_Status):
     *   i  0~ 4 (5건):  PoNumber 끝 '6', InProgress, EffectiveDate=today-7   → 위험
     *   i  5~ 9 (5건):  PoNumber 끝 '9', InProgress, EffectiveDate=today-60  → 대형지연
     *   i 10~59 (50건): PoNumber 끝 0~5, Done/Shipped, 30~120일 전           → 정시·분할입금
     *   i 60~84 (25건): PoNumber 끝 0~5, Shipped, 180~239일 전                → 장기미수 후보
     *   i 85~99 (15건): PoNumber 끝 0~5, Pending/Done, 7~20일 전              → 진행중·일부 입금
     */
    List<Order> orders = new List<Order>();
    for (Integer i = 0; i < 100; i++) {
        Account acc = accounts[Math.mod(i, accounts.size())];

        String poEnd;
        Date effDate;
        String prodStatus;

        if (i < 5) {
            poEnd = '6';
            effDate = TODAY.addDays(-7);
            prodStatus = 'InProgress';
        } else if (i < 10) {
            poEnd = '9';
            effDate = TODAY.addDays(-60);
            prodStatus = 'InProgress';
        } else if (i < 60) {
            poEnd = String.valueOf(Math.mod(i, 6));      // 0~5 순환
            effDate = TODAY.addDays(-(30 + Math.mod(i, 90)));
            prodStatus = (Math.mod(i, 3) == 0) ? 'Done' : 'Shipped';
        } else if (i < 85) {
            poEnd = String.valueOf(Math.mod(i, 6));
            effDate = TODAY.addDays(-(180 + Math.mod(i, 60)));
            prodStatus = 'Shipped';
        } else {
            poEnd = String.valueOf(Math.mod(i, 6));
            effDate = TODAY.addDays(-(7 + Math.mod(i, 14)));
            prodStatus = (Math.mod(i, 2) == 0) ? 'Pending' : 'Done';
        }

        // PoNumber: PO-2026-XXXY (X 3자리 시퀀스, Y 1자리 끝자리)
        String poNumber = 'PO-2026-' + String.valueOf(1000 + i).substring(1) + poEnd;

        orders.add(new Order(
            AccountId = acc.Id,
            Name = 'ORD-' + String.valueOf(1000 + i),
            EffectiveDate = effDate,
            Status = 'Draft',
            Pricebook2Id = stdPb.Id,
            PoNumber = poNumber,
            Production_Status__c = prodStatus,
            Description = SEED_TAG
        ));
    }
    insert orders;
    System.debug('Order: ' + orders.size());

    /* ========== 5. OrderItem (각 Order당 2건, TotalAmount 자동 계산) ========== */
    List<OrderItem> items = new List<OrderItem>();
    Map<Id, Decimal> orderTotals = new Map<Id, Decimal>();
    for (Integer i = 0; i < orders.size(); i++) {
        PricebookEntry p1 = pbes[Math.mod(i, pbes.size())];
        PricebookEntry p2 = pbes[Math.mod(i + 7, pbes.size())];
        Integer q1 = 10 + Math.mod(i, 40);     // 10~49
        Integer q2 = 5  + Math.mod(i * 3, 25); // 5~29
        Decimal total = (q1 * p1.UnitPrice) + (q2 * p2.UnitPrice);
        orderTotals.put(orders[i].Id, total);

        items.add(new OrderItem(
            OrderId = orders[i].Id,
            PricebookEntryId = p1.Id,
            Quantity = q1,
            UnitPrice = p1.UnitPrice
        ));
        items.add(new OrderItem(
            OrderId = orders[i].Id,
            PricebookEntryId = p2.Id,
            Quantity = q2,
            UnitPrice = p2.UnitPrice
        ));
    }
    insert items;
    System.debug('OrderItem: ' + items.size());

    /* ========== 6. Payment__c (분할 입금 + 장기미수) ========== */
    List<Payment__c> payments = new List<Payment__c>();
    List<Order> ordersToUpdate = new List<Order>();

    for (Integer i = 0; i < orders.size(); i++) {
        Order o = orders[i];
        Decimal totalAmt = orderTotals.get(o.Id);
        Decimal paidSum = 0;

        if (i < 10) {
            // 위험·대형지연 (생산중) — 입금 0
            continue;
        } else if (i < 60) {
            // 정시 분할 입금 50건 — Order당 3회 입금
            Decimal third = (totalAmt / 3).setScale(0);
            for (Integer k = 0; k < 3; k++) {
                Decimal amt = (k == 2) ? (totalAmt - paidSum) : third;
                payments.add(new Payment__c(
                    Order__c = o.Id,
                    Paid_Amount__c = amt,
                    Paid_Date__c = o.EffectiveDate.addDays(7 + k * 14),
                    Status__c = 'Paid',
                    Memo__c = SEED_TAG + ' 분할 ' + (k + 1) + '/3'
                ));
                paidSum += amt;
            }
        } else if (i < 85) {
            // 장기미수 25건 — 일부만 1회 부분입금 후 정지 (Outstanding 큼)
            if (Math.mod(i, 3) == 0) {
                Decimal amt = (totalAmt / 3).setScale(0);
                payments.add(new Payment__c(
                    Order__c = o.Id,
                    Paid_Amount__c = amt,
                    Paid_Date__c = o.EffectiveDate.addDays(15),
                    Status__c = 'Paid',
                    Memo__c = SEED_TAG + ' 부분입금'
                ));
                paidSum += amt;
            }
            // 나머지: 입금 0 → Outstanding = TotalAmount
        } else {
            // 최근 진행중 15건 — 절반은 1차 입금
            if (Math.mod(i, 2) == 0) {
                Decimal amt = (totalAmt / 2).setScale(0);
                payments.add(new Payment__c(
                    Order__c = o.Id,
                    Paid_Amount__c = amt,
                    Paid_Date__c = TODAY.addDays(-3),
                    Status__c = 'Paid',
                    Memo__c = SEED_TAG + ' 1차 입금'
                ));
                paidSum += amt;
            }
        }

        if (paidSum > 0) {
            ordersToUpdate.add(new Order(
                Id = o.Id,
                Total_Paid_Amount__c = paidSum
            ));
        }
    }
    insert payments;
    if (!ordersToUpdate.isEmpty()) {
        update ordersToUpdate;
    }
    System.debug('Payment__c: ' + payments.size() + ' / Order paid-update: ' + ordersToUpdate.size());

    /* ========== 7. 검증 카운트 (필터 가능 표준 키 기준) ========== */
    String accLike = SEED_TAG + '-%';
    String prdLike = SEED_TAG + '-SKU-%';
    Set<Id> seedAccIds = new Map<Id, Account>([SELECT Id FROM Account WHERE AccountNumber LIKE :accLike]).keySet();
    Set<Id> seedOrdIds = new Map<Id, Order>([SELECT Id FROM Order WHERE AccountId IN :seedAccIds]).keySet();
    Integer accCount = seedAccIds.size();
    Integer conCount = [SELECT COUNT() FROM Contact    WHERE AccountId IN :seedAccIds];
    Integer prdCount = [SELECT COUNT() FROM Product2   WHERE ProductCode LIKE :prdLike];
    Integer ordCount = seedOrdIds.size();
    Integer payCount = [SELECT COUNT() FROM Payment__c WHERE Order__c IN :seedOrdIds];

    System.debug('--------- SEED RESULT ---------');
    System.debug('Account     : ' + accCount + ' (expect 30)');
    System.debug('Contact     : ' + conCount + ' (expect 60)');
    System.debug('Product2    : ' + prdCount + ' (expect 50)');
    System.debug('Order       : ' + ordCount + ' (expect 100)');
    System.debug('Payment__c  : ' + payCount + ' (expect ~120)');
    System.debug('=== Sales Cockpit Seed Day 2 DONE ===');

} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '!! SEED FAILED — rolled back: ' + e.getTypeName() + ' : ' + e.getMessage());
    System.debug(LoggingLevel.ERROR, e.getStackTraceString());
    throw e;
}
