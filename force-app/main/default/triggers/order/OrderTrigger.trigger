/**
 * OrderTrigger — Order after insert/update 라우터.
 *
 * after insert: Opp 의 수락된 Quote 라인을 OrderItem 으로 자동 복사
 *               (Quote 수락 → Won → Order 자동 동선의 라인 가시화)
 *
 * @group Order
 */
trigger OrderTrigger on Order (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        OrderTriggerHandler.copyQuoteLinesOnInsert(Trigger.new);
    }
}
