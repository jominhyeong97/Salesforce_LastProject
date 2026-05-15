// Refund_Request__c, Shipping_Tracking__c 메타가 org에서 사라졌는지 검증
Map<String, Schema.SObjectType> g = Schema.getGlobalDescribe();
System.debug('Refund_Request__c: ' + (g.containsKey('Refund_Request__c') ? '아직 존재' : '삭제됨'));
System.debug('Shipping_Tracking__c: ' + (g.containsKey('Shipping_Tracking__c') ? '아직 존재' : '삭제됨'));
