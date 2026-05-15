/**
 * OpportunityTrigger
 *   before insert: Pricebook2Id 누락 시 Standard Pricebook 자동 할당
 *                  (downstream Quote/Order 자동화 의존성 보장)
 *   before update: Stage 전환 시 게이트 enforce (FR-OPP-001)
 *   after update : '수주' 전환 시 Order 자동 생성 (Day 9 Case A 마무리, FR-ORDER-001)
 */
trigger OpportunityTrigger on Opportunity (before insert, before update, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        OpportunityTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        OpportunityTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
