/**
 * LeadScoringService — Lead 점수 계산 (FR-LEAD-003)
 * 산식: 채널 가중치 + 과거 거래 보너스 + 사양 입력 + 수량 정보 → 0~100 클램프.
 * Hot 70+, Warm 40~69, Cold <40.
 * Day 5에 사업장 규모(OCR) 가중치 추가 예정 (FR-LEAD-005).
 */
public with sharing class LeadScoringService {

    @TestVisible
    private static final Map<String, Integer> CHANNEL_WEIGHTS = new Map<String, Integer>{
        'PHONE' => 30,
        'EMAIL' => 20,
        'VISIT' => 40
    };

    /**
     * 단건 Lead 점수 계산. SOQL 1회(과거 거래 검사).
     * @param lead 필요 필드: Source_Channel__c, Company, RFQ_Spec_JSON__c
     */
    @AuraEnabled
    public static Integer calculateScore(Lead lead) {
        if (lead == null) return 0;
        Integer score = 0;

        // 1. 채널 가중치
        if (lead.Source_Channel__c != null && CHANNEL_WEIGHTS.containsKey(lead.Source_Channel__c)) {
            score += CHANNEL_WEIGHTS.get(lead.Source_Channel__c);
        }

        // 2. 과거 거래: 같은 회사명 Account 존재 시 +20
        if (String.isNotBlank(lead.Company)) {
            Integer accCount = [SELECT COUNT() FROM Account WHERE Name = :lead.Company];
            if (accCount > 0) score += 20;
        }

        // 3. 사양 입력 +10 / 4. quantity 정보 +10
        if (String.isNotBlank(lead.RFQ_Spec_JSON__c)) {
            score += 10;
            try {
                Map<String, Object> spec = (Map<String, Object>) JSON.deserializeUntyped(lead.RFQ_Spec_JSON__c);
                if (spec.containsKey('quantity') && spec.get('quantity') != null) {
                    score += 10;
                }
            } catch (Exception ignored) {
                // JSON 파싱 실패는 무시
            }
        }

        return Math.min(100, Math.max(0, score));
    }

    /**
     * Lead.Lead_Score__c 갱신. LWC 또는 Trigger에서 호출.
     */
    @AuraEnabled
    public static Lead applyScore(Id leadId) {
        if (leadId == null) return null;
        Lead l = [
            SELECT Id, Source_Channel__c, Company, RFQ_Spec_JSON__c, Lead_Score__c
            FROM Lead WHERE Id = :leadId LIMIT 1
        ];
        l.Lead_Score__c = calculateScore(l);
        update l;
        return l;
    }
}
