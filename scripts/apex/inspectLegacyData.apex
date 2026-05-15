// scripts/apex/inspectLegacyData.apex
// ShopFlow 등 이전 프로젝트 잔재 데이터 조사 (읽기 전용 — 삭제 안 함)
// SEED-D2 시드와 분리해서 식별.
// 실행: sf apex run --file scripts/apex/inspectLegacyData.apex --target-org My_Org

System.debug('=== Legacy Data Inspect ===');

// SEED-D2 Account ID 셋 (이번 프로젝트 시드)
Set<Id> seedAccIds = new Map<Id, Account>(
    [SELECT Id FROM Account WHERE AccountNumber LIKE 'SEED-D2-%']
).keySet();
System.debug('SEED-D2 Account 식별: ' + seedAccIds.size() + ' (정상이면 30)');

/* ---------- 1. SEED-D2가 아닌 Account ---------- */
List<Account> legacyAccs = [
    SELECT Id, Name, AccountNumber, CreatedDate, Owner.Name
    FROM Account
    WHERE Id NOT IN :seedAccIds
    ORDER BY CreatedDate
    LIMIT 200
];
System.debug('---------- Legacy Account: ' + legacyAccs.size() + ' ----------');
for (Account a : legacyAccs) {
    System.debug('  [' + a.AccountNumber + '] ' + a.Name + ' | ' + a.CreatedDate.format() + ' | by ' + a.Owner.Name);
}

/* ---------- 2. SEED-D2 Account에 묶이지 않은 Contact ---------- */
Integer legacyContacts = [SELECT COUNT() FROM Contact WHERE AccountId NOT IN :seedAccIds OR AccountId = NULL];
System.debug('Legacy Contact: ' + legacyContacts);

/* ---------- 3. Case (이번 프로젝트는 아직 Case 안 만듦 → 모두 ShopFlow 잔재 가능성) ---------- */
Integer caseCount = [SELECT COUNT() FROM Case];
System.debug('Case 전체: ' + caseCount);

/* ---------- 4. SEED-D2 외 Order ---------- */
Integer legacyOrders = [SELECT COUNT() FROM Order WHERE AccountId NOT IN :seedAccIds OR AccountId = NULL];
System.debug('Legacy Order: ' + legacyOrders);

/* ---------- 5. SEED-D2 외 Product2 ---------- */
Integer legacyProducts = [SELECT COUNT() FROM Product2 WHERE NOT (ProductCode LIKE 'SEED-D2-SKU-%')];
System.debug('Legacy Product2: ' + legacyProducts);

/* ---------- 6. SEED-D2 외 Lead ---------- */
Integer leadCount = [SELECT COUNT() FROM Lead];
System.debug('Lead 전체: ' + leadCount);

/* ---------- 7. SEED-D2 외 Opportunity ---------- */
Integer oppCount = [SELECT COUNT() FROM Opportunity];
System.debug('Opportunity 전체: ' + oppCount);

/* ---------- 8. ShopFlow 커스텀 객체 존재 여부 (동적 describe) ---------- */
Map<String, Schema.SObjectType> globalDesc = Schema.getGlobalDescribe();
List<String> shopflowObjs = new List<String>{
    'Refund_Request__c', 'Shipping_Tracking__c', 'Customer_Loyalty__c',
    'Order_Inquiry__c', 'Refund__c', 'Loyalty__c'
};
for (String objName : shopflowObjs) {
    if (globalDesc.containsKey(objName)) {
        Integer cnt = Database.countQuery('SELECT COUNT() FROM ' + objName);
        System.debug('[ShopFlow obj] ' + objName + ': 존재 / ' + cnt + '건');
    } else {
        System.debug('[ShopFlow obj] ' + objName + ': 없음');
    }
}

/* ---------- 9. Knowledge (ShopFlow 시연 자료) ---------- */
if (globalDesc.containsKey('Knowledge__kav')) {
    Integer kcnt = Database.countQuery('SELECT COUNT() FROM Knowledge__kav');
    System.debug('Knowledge__kav: ' + kcnt);
}

/* ---------- 10. SEED-D2 외 Payment__c ---------- */
Set<Id> seedOrdIds = new Map<Id, Order>([SELECT Id FROM Order WHERE AccountId IN :seedAccIds]).keySet();
Integer legacyPays = [SELECT COUNT() FROM Payment__c WHERE Order__c NOT IN :seedOrdIds];
System.debug('Legacy Payment__c: ' + legacyPays);

System.debug('=== Inspect DONE ===');
