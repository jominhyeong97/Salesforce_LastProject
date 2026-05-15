// 1) Tests 가 실제로 OrderItem을 만든 게 맞는지, 시드/테스트 데이터 확인
Integer existingOrders = [SELECT COUNT() FROM Order];
Integer existingItems = [SELECT COUNT() FROM OrderItem];
System.debug('현재 Order ' + existingOrders + ' / OrderItem ' + existingItems);

// 2) 가장 최근에 만들어진 Order 가 OpportunityId 를 가졌는지
List<Order> recent = [SELECT Id, Name, AccountId FROM Order ORDER BY CreatedDate DESC LIMIT 3];
for (Order o : recent) {
    System.debug('Order=' + o.Name + ' / Acc=' + o.AccountId);
    // dynamic field access
    Object oppId = o.get('OpportunityId');
    System.debug('  OpportunityId (dynamic): ' + oppId);
}
