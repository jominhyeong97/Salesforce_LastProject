// scripts/apex/simulateRequoteReply.apex
// 시연용 — 고객의 "재견적" 회신 메일을 EmailMessage로 시뮬레이션.
// 트리거(EmailMessageTrigger) → EmailIntentClassifyService @future → Intent='Requote' → QuoteRequoteService 자동 초안
//
// 사용:
//   1) 시연에서 보여줄 Quote 선택 (Status='발송' 또는 '응답대기')
//   2) Quote.Id 를 QUOTE_ID 에 채우거나 그대로 두면 가장 최근 '발송' Quote 자동 선택
//   3) 실행: sf apex run --file scripts/apex/simulateRequoteReply.apex --target-org My_Org
//   4) 약 5~10초 후 해당 Quote 의 Opportunity 에 (재견적) 접미사가 붙은 새 Quote 가 생김

final String QUOTE_NAME_HINT = null;   // 예: 'Q-DEMO-003-동방베어링'. null 이면 자동 선택.

// 1) 대상 Quote 선택 (Opportunity.AccountId 까지 함께 조회)
Quote target;
if (QUOTE_NAME_HINT != null) {
    target = [
        SELECT Id, Name, OpportunityId, Opportunity.AccountId
        FROM Quote WHERE Name = :QUOTE_NAME_HINT LIMIT 1
    ];
} else {
    List<Quote> qs = [
        SELECT Id, Name, OpportunityId, Opportunity.AccountId
        FROM Quote
        WHERE Status IN ('발송', '응답대기')
        ORDER BY Sent_Date__c DESC NULLS LAST
        LIMIT 1
    ];
    if (qs.isEmpty()) {
        throw new System.IllegalArgumentException('발송/응답대기 상태 Quote 가 없습니다. seedData 부터 실행하세요.');
    }
    target = qs[0];
}
System.debug('대상 Quote: ' + target.Name + ' (' + target.Id + ')');

// 2) 그 Account 의 1차 Contact(구매팀/자재팀) → 고객측 발신자로 사용
String fromAddr = 'buyer@customer.example';
String fromName = '구매팀 박과장';
if (target.Opportunity != null && target.Opportunity.AccountId != null) {
    List<Contact> cs = [
        SELECT Id, Name, Email, Korean_Title__c, Korean_Department__c
        FROM Contact
        WHERE AccountId = :target.Opportunity.AccountId AND Email != null
        ORDER BY CreatedDate ASC
        LIMIT 1
    ];
    if (!cs.isEmpty()) {
        fromAddr = cs[0].Email;
        fromName = (cs[0].Korean_Department__c != null ? cs[0].Korean_Department__c + ' ' : '')
                 + (cs[0].Name != null ? cs[0].Name : '담당')
                 + (cs[0].Korean_Title__c != null ? ' ' + cs[0].Korean_Title__c : '');
    }
}
System.debug('회신자: ' + fromName + ' <' + fromAddr + '>');

// 3) "고객 회신" EmailMessage 1건 생성 — Incoming=true, RelatedToId=Quote.Id
EmailMessage em = new EmailMessage(
    Subject     = 'RE: [' + target.Name + '] 견적서 회신',
    FromAddress = fromAddr,
    FromName    = fromName,
    ToAddress   = UserInfo.getUserEmail(),
    TextBody    = '안녕하세요.\n\n' +
                  '보내주신 견적 잘 받아봤습니다.\n' +
                  '단가가 조금 부담스러워서 10% 할인 더 부탁드립니다.\n' +
                  '협의 후 빠른 결정 드리겠습니다.\n\n' +
                  '감사합니다.\n구매팀 박과장 드림',
    Incoming    = true,                    // ← 핵심 — 인바운드 메일로 마킹
    Status      = '0',                     // New
    RelatedToId = target.Id,               // ← 핵심 — Quote 에 연결
    MessageDate = DateTime.now()
);
insert em;
System.debug('회신 EmailMessage 생성: ' + em.Id);
System.debug('  → EmailMessageTrigger 가 자동 발화 → @future 분류 → Intent="Requote" → 자동 재견적 초안');
System.debug('');
System.debug('5~10초 후 다음 SOQL 로 새 Quote 를 확인:');
System.debug('  SELECT Id, Name, Status FROM Quote WHERE OpportunityId = \'' + target.OpportunityId + '\' ORDER BY CreatedDate DESC');
