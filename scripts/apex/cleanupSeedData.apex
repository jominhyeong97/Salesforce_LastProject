// scripts/apex/cleanupSeedData.apex
// Sales Cockpit — Day 2 Seed 일괄 삭제 (SEED-D2)
// 식별 키: Account.AccountNumber LIKE 'SEED-D2-%', Product2.ProductCode LIKE 'SEED-D2-SKU-%'
// 자식은 부모 ID cascade로 식별 (Description은 Long Text라 SOQL 필터 불가).
// 삭제 순서: Payment__c → OrderItem → Order → Contact → Account → PricebookEntry → Product2
//
// 실행: sf apex run --file scripts/apex/cleanupSeedData.apex --target-org My_Org

System.debug('=== Sales Cockpit Seed CLEANUP (SEED-D2) START ===');

final String SEED_TAG = 'SEED-D2';
final String accLike = SEED_TAG + '-%';
final String prdLike = SEED_TAG + '-SKU-%';

Set<Id> seedAccIds = new Map<Id, Account>(
    [SELECT Id FROM Account WHERE AccountNumber LIKE :accLike]
).keySet();
Set<Id> seedOrdIds = new Map<Id, Order>(
    [SELECT Id FROM Order WHERE AccountId IN :seedAccIds]
).keySet();

List<Payment__c> pays = [SELECT Id FROM Payment__c WHERE Order__c IN :seedOrdIds];
delete pays;
System.debug('Payment__c deleted: ' + pays.size());

List<OrderItem> items = [SELECT Id FROM OrderItem WHERE OrderId IN :seedOrdIds];
delete items;
System.debug('OrderItem deleted: ' + items.size());

List<Order> orders = [SELECT Id FROM Order WHERE Id IN :seedOrdIds];
delete orders;
System.debug('Order deleted: ' + orders.size());

List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId IN :seedAccIds];
delete contacts;
System.debug('Contact deleted: ' + contacts.size());

List<Account> accs = [SELECT Id FROM Account WHERE Id IN :seedAccIds];
delete accs;
System.debug('Account deleted: ' + accs.size());

// Product2 삭제 전 PricebookEntry 먼저
List<Product2> products = [SELECT Id FROM Product2 WHERE ProductCode LIKE :prdLike];
List<PricebookEntry> pbes = [SELECT Id FROM PricebookEntry WHERE Product2Id IN :products];
delete pbes;
System.debug('PricebookEntry deleted: ' + pbes.size());

delete products;
System.debug('Product2 deleted: ' + products.size());

System.debug('=== CLEANUP DONE ===');
