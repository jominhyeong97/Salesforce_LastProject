Map<String, Schema.SObjectField> fmap = Order.SObjectType.getDescribe().fields.getMap();
System.debug('case-insensitive opportunityid: ' + fmap.containsKey('opportunityid'));
System.debug('case-insensitive opportunity__c: ' + fmap.containsKey('opportunity__c'));
System.debug('total fields: ' + fmap.size());
// 모든 'op' 접두 field
for (String k : fmap.keySet()) {
    if (k.startsWith('op')) System.debug('  ' + k);
}
