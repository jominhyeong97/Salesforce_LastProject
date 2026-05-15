// Order의 모든 lookup/reference 필드 확인
Schema.DescribeSObjectResult dsr = Order.SObjectType.getDescribe();
Map<String, Schema.SObjectField> fmap = dsr.fields.getMap();
for (String key : fmap.keySet()) {
    Schema.DescribeFieldResult fd = fmap.get(key).getDescribe();
    if (fd.getType() == Schema.DisplayType.REFERENCE) {
        System.debug(fd.getName() + ' → ' + fd.getReferenceTo());
    }
}
