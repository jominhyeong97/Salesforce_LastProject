// 기존 EMAIL Lead 의 Lead_Score__c 보정 (RfqInboundHandler 갱신 전 생성된 record).
List<Lead> emailLeads = [
    SELECT Id, Source_Channel__c, Company, RFQ_Spec_JSON__c, Lead_Score__c
    FROM Lead WHERE Source_Channel__c = 'EMAIL' AND Lead_Score__c = NULL
];
System.debug('점수 미계산 EMAIL Lead: ' + emailLeads.size());
for (Lead l : emailLeads) {
    l.Lead_Score__c = LeadScoringService.calculateScore(l);
    System.debug('  ' + l.Company + ' → ' + l.Lead_Score__c);
}
if (!emailLeads.isEmpty()) update emailLeads;
System.debug('Score 갱신: ' + emailLeads.size());
