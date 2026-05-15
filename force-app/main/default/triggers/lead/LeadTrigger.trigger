/**
 * LeadTrigger — Lead Convert 시 후속 매핑 (FR-LEAD-004).
 * AfterUpdate 에서 IsConverted 전이를 감지, ConvertedOpportunity에 RFQ 사양 자동 복사.
 */
trigger LeadTrigger on Lead (after update) {
    LeadTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}
