/**
 * LeadTriggerHandler — FR-LEAD-004 Lead Convert 자동 매핑.
 * IsConverted 전이 시점에 Lead.RFQ_Spec_JSON__c → ConvertedOpportunity.Description 복사.
 * (PRD: 사양 → Opp 복사. Opportunity.StageName 의 default('발굴')는 OpportunityStage StandardValueSet 으로 정비됨.)
 *
 * with sharing, bulkified, single SOQL.
 */
public with sharing class LeadTriggerHandler {

    public static void handleAfterUpdate(List<Lead> newList, Map<Id, Lead> oldMap) {
        if (newList == null || oldMap == null) return;

        Map<Id, Lead> oppIdToLead = new Map<Id, Lead>();
        for (Lead l : newList) {
            Lead old = oldMap.get(l.Id);
            if (old == null) continue;
            // IsConverted 가 false → true 로 전이된 시점만
            if (l.IsConverted && !old.IsConverted && l.ConvertedOpportunityId != null) {
                oppIdToLead.put(l.ConvertedOpportunityId, l);
            }
        }

        if (oppIdToLead.isEmpty()) return;

        List<Opportunity> toUpdate = new List<Opportunity>();
        for (Id oppId : oppIdToLead.keySet()) {
            Lead l = oppIdToLead.get(oppId);
            // RFQ 사양이 있는 Lead만 — 사양 없으면 건너뜀
            if (String.isBlank(l.RFQ_Spec_JSON__c)) continue;
            toUpdate.add(new Opportunity(
                Id = oppId,
                Description = l.RFQ_Spec_JSON__c
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
