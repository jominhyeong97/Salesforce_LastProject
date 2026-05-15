// scripts/apex/verifySeedData.apex
// Day 2 시드 후 분포 검증. 골든패스 8단계(ERP 동기화 → 위험 5건) 사전 보장.
// 실행: sf apex run --file scripts/apex/verifySeedData.apex --target-org My_Org

System.debug('=== Sales Cockpit Seed VERIFY ===');

final String SEED_TAG = 'SEED-D2';
final String accLike = SEED_TAG + '-%';

Set<Id> seedAccIds = new Map<Id, Account>(
    [SELECT Id FROM Account WHERE AccountNumber LIKE :accLike]
).keySet();

// 위험 후보: PoNumber 끝 '6' AND Production_Status='InProgress'
List<Order> riskOrders = [
    SELECT Id, PoNumber, Production_Status__c, EffectiveDate, TotalAmount
    FROM Order
    WHERE AccountId IN :seedAccIds AND Production_Status__c = 'InProgress'
    ORDER BY PoNumber
];
Integer risk = 0;
Integer late = 0;
for (Order o : riskOrders) {
    String last = o.PoNumber.substring(o.PoNumber.length() - 1);
    if (last == '6' || last == '7' || last == '8') risk++;
    else if (last == '9') late++;
}

// 정시 — Done/Shipped/Pending
Integer onTime = [
    SELECT COUNT() FROM Order
    WHERE AccountId IN :seedAccIds AND Production_Status__c != 'InProgress'
];

// 장기미수 후보: Outstanding > 0 AND EffectiveDate 180일 이전
Integer longDebt = [
    SELECT COUNT() FROM Order
    WHERE AccountId IN :seedAccIds
      AND Outstanding_Amount__c > 0
      AND EffectiveDate < :Date.today().addDays(-180)
];

// 분할 입금 Order (COUNT_DISTINCT는 AggregateResult)
AggregateResult ar = [
    SELECT COUNT_DISTINCT(Order__c) cnt FROM Payment__c
    WHERE Order__r.AccountId IN :seedAccIds
];
Integer splitPaid = (Integer) ar.get('cnt');

// Total_Paid_Amount 갱신된 Order
Integer paidOrders = [
    SELECT COUNT() FROM Order
    WHERE AccountId IN :seedAccIds AND Total_Paid_Amount__c > 0
];

// 사업자번호 자동 하이픈 포맷팅 검증 (XXX-XX-XXXXX)
List<Account> bnSamples = [
    SELECT Name, Business_Number__c FROM Account
    WHERE AccountNumber LIKE :accLike
    ORDER BY AccountNumber LIMIT 3
];

System.debug('=========== 분포 검증 ===========');
System.debug('위험 후보 (InProgress + 끝6/7/8): ' + risk + ' (expect 5)');
System.debug('대형지연 (InProgress + 끝9)     : ' + late + ' (expect 5)');
System.debug('정시 (Done/Shipped/Pending)     : ' + onTime + ' (expect 90)');
System.debug('장기미수 후보 (180일+ 미입금)   : ' + longDebt + ' (expect ~16)');
System.debug('분할/부분 입금 Order            : ' + splitPaid + ' (expect ~66)');
System.debug('Total_Paid_Amount 갱신          : ' + paidOrders + ' (expect 66)');

System.debug('=========== 사업자번호 샘플 ===========');
for (Account a : bnSamples) {
    System.debug(a.Name + ' → ' + a.Business_Number__c);
}

System.debug('=== VERIFY DONE ===');
