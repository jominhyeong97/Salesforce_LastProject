/**
 * EmailMessageTriggerHandler — 수신 메일 자동 의도 분류 진입.
 *
 * Incoming=true + RelatedTo(Quote|Opportunity) 인 EmailMessage 만 모아
 * EmailIntentClassifyService.classifyAsync(@future)로 디스패치.
 * 응답 시간이 길 수 있는 LLM 호출은 비동기로 격리.
 *
 * FR-QUOTE-007, FR-QUOTE-009.
 *
 * @group Quote
 */
public with sharing class EmailMessageTriggerHandler {

    @TestVisible private static final Set<String> TARGETED_TYPES = new Set<String>{
        'Quote', 'Opportunity'
    };

    public static void handleAfterInsert(List<EmailMessage> newList) {
        if (newList == null || newList.isEmpty()) return;

        List<Id> targets = new List<Id>();
        for (EmailMessage em : newList) {
            if (em.Incoming != true)        continue;
            if (em.RelatedToId == null)     continue;
            String typeName = em.RelatedToId.getSObjectType().getDescribe().getName();
            if (!TARGETED_TYPES.contains(typeName)) continue;
            targets.add(em.Id);
        }
        if (targets.isEmpty()) return;

        // @future는 트리거 같은 트랜잭션에서 호출 가능
        EmailIntentClassifyService.classifyAsync(targets);
    }
}
