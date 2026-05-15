// scripts/apex/cleanupShopFlowData.apex
// ShopFlow 잔재 데이터 일괄 삭제 — SEED-D2 시드 (AccountNumber LIKE 'SEED-D2-%') 보존.
// 실행: sf apex run --file scripts/apex/cleanupShopFlowData.apex --target-org My_Org

System.debug('=== ShopFlow Data Cleanup START ===');

Set<Id> seedAccIds = new Map<Id, Account>(
    [SELECT Id FROM Account WHERE AccountNumber LIKE 'SEED-D2-%']
).keySet();
System.debug('SEED-D2 Account 보존: ' + seedAccIds.size());

/* 1. Knowledge — Online은 archive로 전환만. master 삭제는 Apex 미지원 → Setup UI에서 수동.
 *    가이드: Setup → Knowledge Articles → Filter "Archived" → 일괄 선택 → Delete (10건 1분). */
List<Knowledge__kav> kavs = [SELECT Id, KnowledgeArticleId, PublishStatus, Title FROM Knowledge__kav];
System.debug('Knowledge__kav 발견: ' + kavs.size());
Integer archivedCnt = 0;
for (Knowledge__kav v : kavs) {
    if (v.PublishStatus == 'Online') {
        try {
            KbManagement.PublishingService.archiveOnlineArticle(String.valueOf(v.KnowledgeArticleId), null);
            archivedCnt++;
        } catch (Exception e) {
            System.debug('archive 실패 [' + v.Title + ']: ' + e.getMessage());
        }
    }
}
System.debug('Online → Archived 전환: ' + archivedCnt + ' / 발견 ' + kavs.size());
System.debug('>> Knowledge 삭제는 Setup → Knowledge Articles → Archived 필터 → 일괄 Delete (1분)');

/* 2. Case (자식 CaseComment/EmailMessage 자동 cascade) */
List<Case> cases = [SELECT Id FROM Case];
delete cases;
System.debug('Case 삭제: ' + cases.size());

/* 3. Opportunity (자식 OpportunityLineItem 자동 cascade) */
List<Opportunity> opps = [SELECT Id FROM Opportunity];
delete opps;
System.debug('Opportunity 삭제: ' + opps.size());

/* 4. Order — Activated 는 직접 삭제 불가 → Status='Draft'로 reset 후 자식 삭제, Order 삭제 */
List<Order> legacyOrders = [SELECT Id, Status FROM Order WHERE AccountId NOT IN :seedAccIds OR AccountId = NULL];
List<Order> toReset = new List<Order>();
for (Order o : legacyOrders) {
    if (o.Status != 'Draft') {
        toReset.add(new Order(Id = o.Id, Status = 'Draft'));
    }
}
if (!toReset.isEmpty()) {
    update toReset;
    System.debug('Activated Order → Draft reset: ' + toReset.size());
}
List<OrderItem> legacyItems = [SELECT Id FROM OrderItem WHERE OrderId IN :legacyOrders];
delete legacyItems;
System.debug('Legacy OrderItem 삭제: ' + legacyItems.size());
delete legacyOrders;
System.debug('Legacy Order 삭제: ' + legacyOrders.size());

/* 5. Lead */
List<Lead> leads = [SELECT Id FROM Lead];
delete leads;
System.debug('Lead 삭제: ' + leads.size());

/* 6. Contact — SEED-D2 Account 자식이 아닌 것만 */
List<Contact> legacyContacts = [SELECT Id FROM Contact WHERE AccountId NOT IN :seedAccIds OR AccountId = NULL];
delete legacyContacts;
System.debug('Legacy Contact 삭제: ' + legacyContacts.size());

/* 7. Account — SEED-D2 외. 표준 Sample Account(Entitlement 의존) 등 dependency 있는 건 partial-success 로 skip */
List<Account> legacyAccs = [SELECT Id, Name FROM Account WHERE Id NOT IN :seedAccIds];
Database.DeleteResult[] accResults = Database.delete(legacyAccs, false);
Integer accOk = 0;
for (Integer i = 0; i < accResults.size(); i++) {
    if (accResults[i].isSuccess()) {
        accOk++;
    } else {
        System.debug('Acc skip [' + legacyAccs[i].Name + ']: ' + accResults[i].getErrors()[0].getMessage());
    }
}
System.debug('Legacy Account 삭제: ' + accOk + ' / ' + legacyAccs.size());

/* 8. Product2 — SEED-D2 외 (PricebookEntry 먼저) */
List<Product2> legacyPrds = [SELECT Id FROM Product2 WHERE NOT (ProductCode LIKE 'SEED-D2-SKU-%')];
List<PricebookEntry> legacyPbes = [SELECT Id FROM PricebookEntry WHERE Product2Id IN :legacyPrds];
delete legacyPbes;
System.debug('Legacy PricebookEntry 삭제: ' + legacyPbes.size());
delete legacyPrds;
System.debug('Legacy Product2 삭제: ' + legacyPrds.size());

/* 9. ShopFlow custom 객체 데이터 (메타 삭제 전 비움) */
Map<String, Schema.SObjectType> g = Schema.getGlobalDescribe();
if (g.containsKey('Refund_Request__c')) {
    List<SObject> rrs = Database.query('SELECT Id FROM Refund_Request__c');
    if (!rrs.isEmpty()) delete rrs;
    System.debug('Refund_Request__c 삭제: ' + rrs.size());
}
if (g.containsKey('Shipping_Tracking__c')) {
    List<SObject> sts = Database.query('SELECT Id FROM Shipping_Tracking__c');
    if (!sts.isEmpty()) delete sts;
    System.debug('Shipping_Tracking__c 삭제: ' + sts.size());
}

/* 검증 */
Integer remainAccs = [SELECT COUNT() FROM Account];
Integer remainContacts = [SELECT COUNT() FROM Contact];
Integer remainOrders = [SELECT COUNT() FROM Order];
Integer remainCases = [SELECT COUNT() FROM Case];
Integer remainLeads = [SELECT COUNT() FROM Lead];
Integer remainOpps = [SELECT COUNT() FROM Opportunity];
Integer remainProducts = [SELECT COUNT() FROM Product2];
System.debug('--- 잔여 (SEED-D2 만 남아야) ---');
System.debug('Account: ' + remainAccs + ' (expect 30)');
System.debug('Contact: ' + remainContacts + ' (expect 60)');
System.debug('Order: ' + remainOrders + ' (expect 100)');
System.debug('Product2: ' + remainProducts + ' (expect 50)');
System.debug('Case: ' + remainCases + ' / Lead: ' + remainLeads + ' / Opportunity: ' + remainOpps + ' (expect 0/0/0)');

System.debug('=== ShopFlow Data Cleanup DONE ===');
