/**
 * QuoteFollowupScheduler — 7일 무응답 견적에 AE follow-up Task 자동 생성 (FR-QUOTE-008).
 *
 * 룰 (D13 단일 기준):
 *   - Quote.Status = '발송'
 *   - Quote.Sent_Date__c <= today - 7
 *   - Quote.Last_Opened_At__c IS NULL  (열람 추적 미발생 — 진짜 무응답)
 *   - 같은 Quote 에 미완료 follow-up Task 가 없음 (멱등성)
 *
 * 안전 정책 (D26 일관): 가격·할인 변경 없음. Task 자동 생성 + AE 가 수동 응대.
 *
 * 등록: 한 번만 — Anonymous Apex
 *   QuoteFollowupScheduler.scheduleDaily();
 *
 * @group Quote
 */
public with sharing class QuoteFollowupScheduler implements Schedulable {

    @TestVisible public static final Integer THRESHOLD_DAYS = 7;
    @TestVisible public static final String TASK_SUBJECT_PREFIX = '[견적 Follow-up] ';

    public void execute(SchedulableContext sc) {
        process();
    }

    /** AE/데모 수동 실행 가능. 생성된 Task 수 반환. */
    @AuraEnabled
    public static Integer process() {
        DateTime cutoff = Datetime.newInstance(
            Date.today().addDays(-THRESHOLD_DAYS), Time.newInstance(23, 59, 59, 0)
        );

        List<Quote> candidates = [
            SELECT Id, Name, OpportunityId, Opportunity.OwnerId, Account.Name, Sent_Date__c
            FROM Quote
            WHERE Status = '발송'
              AND Sent_Date__c != null
              AND Sent_Date__c <= :cutoff
              AND Last_Opened_At__c = null
            LIMIT 200
        ];
        if (candidates.isEmpty()) return 0;

        // 이미 미완료 follow-up Task 있는 Quote 제외 (멱등성)
        Set<Id> quoteIds = new Map<Id, Quote>(candidates).keySet();
        Set<Id> alreadyHasTask = new Set<Id>();
        for (Task t : [
            SELECT WhatId FROM Task
            WHERE WhatId IN :quoteIds
              AND Subject LIKE :(TASK_SUBJECT_PREFIX + '%')
              AND IsClosed = false
        ]) {
            alreadyHasTask.add(t.WhatId);
        }

        List<Task> toInsert = new List<Task>();
        for (Quote q : candidates) {
            if (alreadyHasTask.contains(q.Id)) continue;
            Long days = (Date.today().daysBetween(q.Sent_Date__c.date())) * -1;
            toInsert.add(new Task(
                WhatId       = q.Id,
                Subject      = TASK_SUBJECT_PREFIX + q.Name,
                Description  = (q.Account != null ? q.Account.Name : '고객사') + ' 견적 ' + q.Name +
                                ' 발송 후 ' + days + '일 응답 없음. follow-up 메일 또는 전화 권장.',
                Priority     = 'High',
                Status       = 'Not Started',
                ActivityDate = Date.today(),
                OwnerId      = (q.Opportunity != null && q.Opportunity.OwnerId != null)
                                ? q.Opportunity.OwnerId
                                : UserInfo.getUserId()
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
        return toInsert.size();
    }

    /** 데모 편의 — 매일 새벽 4시 스케줄 등록. */
    public static String scheduleDaily() {
        return System.schedule(
            'QuoteFollowupDaily',
            '0 0 4 * * ?',
            new QuoteFollowupScheduler()
        );
    }
}
