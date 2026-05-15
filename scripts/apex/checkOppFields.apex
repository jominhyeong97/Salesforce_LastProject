Map<String, Schema.SObjectField> fmap = Opportunity.SObjectType.getDescribe().fields.getMap();
System.debug('has syncedquoteid: ' + fmap.containsKey('syncedquoteid'));
if (fmap.containsKey('syncedquoteid')) {
    System.debug('Name: ' + fmap.get('syncedquoteid').getDescribe().getName());
}
