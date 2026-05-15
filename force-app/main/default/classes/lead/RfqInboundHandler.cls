/**
 * RfqInboundHandler — EMAIL 채널 Lead 자동 생성 (FR-LEAD-001).
 * Email Service `RfqInbound` 의 entry point. rfq@hando.example 수신 → Lead INSERT.
 * 본문 추출은 CallMemoExtractService 재사용 (Day 5 Prompt Builder SpecExtract 연결 전까지 mock).
 *
 * 활성화: Setup → Email Services → New Email Service
 *   - Apex Class = RfqInboundHandler
 *   - Email Address = rfq@hando.example  (Inbound: Active = true)
 */
global with sharing class RfqInboundHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope env
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        result.success = false;

        try {
            String body = email.plainTextBody != null ? email.plainTextBody : '';
            String fromAddr = email.fromAddress != null ? email.fromAddress : '';
            String fromName = email.fromName;

            // 본문 추출 — SpecExtract Prompt(메일 subject+body 컨텍스트 특화).
            // AI 실패 시 SpecExtractService 내부에서 CallMemoExtract(AI+정규식)로 fallback.
            Map<String, String> ext = SpecExtractService.extract(email.subject, body);

            // 회사명: 본문 추출 우선 → fromName → 도메인 fallback
            String company = String.isNotBlank(ext.get('company'))
                ? ext.get('company')
                : (String.isNotBlank(fromName) ? fromName : extractDomain(fromAddr));

            // 담당자: fromName 우선
            String lastName = String.isNotBlank(fromName) ? fromName : (String.isNotBlank(fromAddr) ? fromAddr : 'Unknown');

            Map<String, Object> spec = new Map<String, Object>{
                'partName' => ext.get('partName'),
                'quantity' => String.isNotBlank(ext.get('quantity')) ? Integer.valueOf(ext.get('quantity')) : null,
                'requestedDate' => ext.get('requestedDate'),
                'rawSubject' => email.subject
            };

            String descPrefix = email.subject != null ? '제목: ' + email.subject + '\n\n' : '';

            Lead l = new Lead(
                Company = company,
                LastName = lastName,
                Email = fromAddr,
                Phone = ext.get('phone'),
                Source_Channel__c = 'EMAIL',
                Status = '신규',
                RFQ_Spec_JSON__c = JSON.serialize(spec),
                Description = descPrefix + body
            );
            insert l;

            // Lead Score 자동 계산 (LeadScoringService) — LWC 인입과 일관성
            l.Lead_Score__c = LeadScoringService.calculateScore(l);
            update l;

            result.success = true;
        } catch (Exception e) {
            result.message = 'RfqInbound 실패: ' + e.getMessage();
        }
        return result;
    }

    /** 'kim@hyundai-mobis.co.kr' → 'hyundai-mobis' */
    @TestVisible
    private static String extractDomain(String fromAddress) {
        if (String.isBlank(fromAddress) || !fromAddress.contains('@')) return 'Unknown';
        String domain = fromAddress.split('@')[1];
        if (String.isBlank(domain)) return 'Unknown';
        return domain.split('\\.')[0];
    }
}
