List<Lead> leads = [SELECT Id, Name, Company, Source_Channel__c, RFQ_Spec_JSON__c
                    FROM Lead WHERE IsConverted=false AND Lead_Score__c=null];
List<Lead> toUpdate = new List<Lead>();
for (Lead l : leads) {
    Integer score = LeadScoringService.calculateScore(l);
    l.Lead_Score__c = score;
    toUpdate.add(l);
}
update toUpdate;

List<Lead> after = [SELECT Name, Source_Channel__c, Lead_Score__c FROM Lead WHERE IsConverted=false ORDER BY Lead_Score__c DESC NULLS LAST LIMIT 10];
for (Lead l : after) System.debug(l.Name + ' (' + l.Source_Channel__c + ') = ' + l.Lead_Score__c);
System.debug('Scored ' + toUpdate.size() + ' Leads');
