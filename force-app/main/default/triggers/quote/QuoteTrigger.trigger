/**
 * QuoteTrigger — Quote 자동화 룰 진입점 (D37).
 *
 *   before insert: Account 주소·연락처 자동 복사 (AE 입력 부담 0)
 *   after update : Status '수락' 전이 시 QuoteLineItem → OpportunityLineItem 자동 동기화
 *                  (Quote.IsSyncing 표준 필드는 read-only — 직접 라인 복사로 동일 효과)
 */
trigger QuoteTrigger on Quote (before insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        QuoteTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        QuoteTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
