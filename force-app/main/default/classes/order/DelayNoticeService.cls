/**
 * DelayNoticeService — 납기 지연 사전 통보 메일 한국어 초안 (FR-ORDER-004).
 *
 * orderRiskCard 의 [✉️ 사전 통보 메일] 버튼 → 본 서비스 호출 → AI subject+body 반환 →
 *  LWC 가 mailto: 컴포저 호출. AI 실패 시 Apex fallback 한국어 정중체 템플릿.
 *
 * 안전 정책 (D26): 가격·할인·새 납기일 임의 제시 금지. 정보·약속만.
 *
 * @group Order
 */
public with sharing class DelayNoticeService {

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'DelayNotice';
    @TestVisible public static String lastSource;

    @AuraEnabled
    public static Draft draft(Id orderId, String additionalContext) {
        if (orderId == null) throw newAura('orderId is required');

        Order o = [
            SELECT Id, OrderNumber, PoNumber, Production_Status__c, Delivery_Risk_Score__c,
                   Account.Name
            FROM Order WHERE Id = :orderId LIMIT 1
        ];

        Draft d = new Draft();
        d.accountName = o.Account != null ? o.Account.Name : '고객사';
        d.orderRef = String.isNotBlank(o.PoNumber) ? o.PoNumber : o.OrderNumber;
        d.riskScore = (Integer) (o.Delivery_Risk_Score__c == null ? 0 : o.Delivery_Risk_Score__c);

        try {
            String aiJson = DelayNoticeInvoker.invoke(TEMPLATE_DEV_NAME, orderId, additionalContext);
            if (String.isBlank(aiJson)) throw new DelayNoticeException('Empty AI body');
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(stripCodeFences(aiJson));
            d.subject = String.valueOf(raw.get('subject'));
            d.body = String.valueOf(raw.get('body'));
            if (String.isBlank(d.subject) || String.isBlank(d.body)) {
                throw new DelayNoticeException('AI subject or body blank');
            }
            d.aiSource = 'ai';
            lastSource = 'ai';
        } catch (Exception e) {
            d.subject = buildFallbackSubject(d.orderRef);
            d.body = buildFallbackBody(d.accountName, d.orderRef);
            d.aiSource = 'fallback';
            d.aiError = e.getMessage();
            lastSource = 'fallback';
        }
        return d;
    }

    @TestVisible
    private static String stripCodeFences(String body) {
        if (String.isBlank(body)) return body;
        String trimmed = body.trim();
        if (!trimmed.startsWith('`')) return trimmed;
        Pattern p = Pattern.compile('(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$');
        Matcher m = p.matcher(trimmed);
        return m.matches() ? m.group(1) : trimmed;
    }

    @TestVisible
    private static String buildFallbackSubject(String orderRef) {
        return '[한도정밀] ' + (orderRef == null ? '주문' : orderRef) + ' 납기 지연 사전 통보';
    }

    @TestVisible
    private static String buildFallbackBody(String accountName, String orderRef) {
        return (accountName == null ? '고객사' : accountName) + ' 담당자님,\n\n' +
               '한도정밀 영업팀입니다. 발주하신 ' + (orderRef == null ? '주문' : orderRef) +
               ' 건 관련 생산 라인 상황으로 출고가 지연될 가능성이 있어 사전 안내드립니다.\n\n' +
               '당사에서 즉시 라인 점검 후 조정 일정을 회신드리겠습니다.\n' +
               '불편을 드려 죄송합니다.\n\n' +
               '한도정밀 영업팀 드림';
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    public class Draft {
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String accountName;
        @AuraEnabled public String orderRef;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String aiSource;     // 'ai' | 'fallback'
        @AuraEnabled public String aiError;
    }

    public class DelayNoticeException extends Exception {}
}
