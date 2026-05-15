@isTest
private class LeadTriggerHandlerTest {

    @isTest
    static void testConvertCopiesSpecToOpp() {
        Lead l = new Lead(
            Company = '테스트정밀',
            LastName = '김',
            Source_Channel__c = 'PHONE',
            RFQ_Spec_JSON__c = '{"partName":"베어링","quantity":50}'
        );
        insert l;

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        LeadStatus convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1];
        lc.setConvertedStatus(convertedStatus.MasterLabel);

        Test.startTest();
        Database.LeadConvertResult lcr = Database.convertLead(lc);
        Test.stopTest();

        System.assert(lcr.isSuccess(), 'Convert 실패: ' + lcr.getErrors());

        Opportunity opp = [SELECT Id, Description FROM Opportunity WHERE Id = :lcr.getOpportunityId()];
        System.assertNotEquals(null, opp.Description, 'Opp.Description 비어있음');
        System.assert(opp.Description.contains('베어링'), 'Opp.Description: ' + opp.Description);
    }

    @isTest
    static void testConvertWithoutSpecSkips() {
        Lead l = new Lead(
            Company = '테스트정밀2',
            LastName = '박',
            Source_Channel__c = 'PHONE'
            // RFQ_Spec_JSON__c 없음
        );
        insert l;

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l.Id);
        LeadStatus convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1];
        lc.setConvertedStatus(convertedStatus.MasterLabel);

        Test.startTest();
        Database.LeadConvertResult lcr = Database.convertLead(lc);
        Test.stopTest();

        System.assert(lcr.isSuccess(), 'Convert 실패: ' + lcr.getErrors());

        Opportunity opp = [SELECT Id, Description FROM Opportunity WHERE Id = :lcr.getOpportunityId()];
        // 사양 없으면 Description 변경 안 됨 (null 또는 표준 default)
        System.assert(String.isBlank(opp.Description) || !opp.Description.contains('partName'),
            'Description: ' + opp.Description);
    }

    @isTest
    static void testNullArgsSafe() {
        // 직접 handler 호출 — null 안전
        LeadTriggerHandler.handleAfterUpdate(null, null);
        LeadTriggerHandler.handleAfterUpdate(new List<Lead>(), new Map<Id, Lead>());
        // Exception 안 남으면 통과
    }

    @isTest
    static void testNoIsConvertedTransitionSkips() {
        // Convert 아닌 일반 Update — handler가 skip 해야
        Lead l = new Lead(Company = 'NoConvCo', LastName = 'X', Source_Channel__c = 'PHONE');
        insert l;
        l.LastName = 'Y';
        Test.startTest();
        update l;
        Test.stopTest();
        // Trigger 가 fire 되지만 IsConverted false → false 라 skip
        // Exception 없으면 OK
    }
}
