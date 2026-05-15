/**
 * StageGateService — Opportunity 단계 전환 게이트 (FR-OPP-001).
 * 게이트 룰 설계:
 *   1. 발굴 → 견적 작성: Account.Business_Number__c (사업자번호)
 *   2. 견적 작성 → 견적 발송: QuoteLineItem 1+ / PDF 생성 / Status='Draft'
 *   3. 견적 발송 → 협상: Quote.Status='Sent' (실제 발송 완료)
 * LWC stageGateChecklist + OpportunityTriggerHandler 공유 호출.
 */
public with sharing class StageGateService {

    public static final String STAGE_DISCOVERY = '발굴';
    public static final String STAGE_QUOTE_BUILDING = '견적 작성';
    public static final String STAGE_QUOTE_SENT = '견적 발송';
    public static final String STAGE_NEGOTIATION = '협상';
    public static final String STAGE_WON = '수주';
    public static final String STAGE_LOST = '실주';

    public class GateResult {
        @AuraEnabled public Boolean passed;
        @AuraEnabled public String currentStage;
        @AuraEnabled public String nextStage;
        @AuraEnabled public List<GateRule> rules;
    }

    public class GateRule {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean satisfied;
        @AuraEnabled public String hintText;

        public GateRule(String label, Boolean satisfied, String hintText) {
            this.label = label;
            this.satisfied = satisfied;
            this.hintText = hintText;
        }
    }

    /** LWC 호출용 — 현재 Opp 의 게이트 상태 반환 (현 Stage → 다음 권장 Stage). */
    @AuraEnabled(cacheable=true)
    public static GateResult checkOppGate(Id opportunityId) {
        if (opportunityId == null) return null;

        Opportunity o = [
            SELECT Id, StageName, Description, Promised_Delivery_Date__c,
                   AccountId, Account.Business_Number__c,
                   (SELECT Id FROM OpportunityContactRoles)
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        String fromStage = o.StageName;
        String toStage = nextStage(fromStage);

        GateResult r = new GateResult();
        r.currentStage = fromStage;
        r.nextStage = toStage;
        r.rules = evaluateRules(o, fromStage, toStage, opportunityId);
        r.passed = isAllSatisfied(r.rules);
        return r;
    }

    /** Trigger 호출용 — 단계 전환 검증. 미충족 룰만 반환 (empty 면 통과). */
    public static List<GateRule> evaluateFailures(Opportunity o, String fromStage, String toStage) {
        List<GateRule> failures = new List<GateRule>();
        for (GateRule g : evaluateRules(o, fromStage, toStage, o.Id)) {
            if (!g.satisfied) failures.add(g);
        }
        return failures;
    }

    /** 룰 평가 — 전환 매핑 별 룰. 매핑되지 않은 전환은 항상 통과(빈 list). */
    @TestVisible
    private static List<GateRule> evaluateRules(Opportunity o, String fromStage, String toStage, Id oppId) {
        List<GateRule> rules = new List<GateRule>();

        if (fromStage == STAGE_DISCOVERY && toStage == STAGE_QUOTE_BUILDING) {
            rules.add(new GateRule(
                '사업자번호 등록',
                String.isNotBlank(o.Account?.Business_Number__c),
                'Account 사업자등록증 업로드 또는 직접 입력'
            ));
            rules.add(new GateRule(
                '약속 납기일 등록',
                o.Promised_Delivery_Date__c != null,
                '납기일을 저장해주세요'
            ));
        }
        else if (fromStage == STAGE_QUOTE_BUILDING && toStage == STAGE_QUOTE_SENT) {
            Map<String, Boolean> quoteStatus = checkQuoteReadiness(oppId);
            rules.add(new GateRule(
                '견적 존재',
                quoteStatus.get('quoteExists'),
                'Quote Builder에서 견적 생성 필요'
            ));
            rules.add(new GateRule(
                '견적 라인',
                quoteStatus.get('hasLineItems'),
                '견적 라인 1개 이상 추가 필요'
            ));
            rules.add(new GateRule(
                '견적 첨부 파일',
                quoteStatus.get('hasAttachment'),
                '견적서 PDF 생성 또는 직접 업로드 (Files 영역에 1개 이상)'
            ));
        }
        else if (fromStage == STAGE_QUOTE_SENT && toStage == STAGE_NEGOTIATION) {
            Map<String, Boolean> quoteStatus = checkQuoteReadiness(oppId);
            rules.add(new GateRule(
                '고객 수락',
                quoteStatus.get('isAccepted'),
                '고객이 견적을 수락한 상태여야 합니다 (Quote.Status=수락)'
            ));
        }

        return rules;
    }

    /** Quote 준비 상태 확인 */
    private static Map<String, Boolean> checkQuoteReadiness(Id oppId) {
        Map<String, Boolean> status = new Map<String, Boolean>{
            'quoteExists'   => false,
            'hasLineItems'  => false,
            'isAccepted'    => false,
            'hasAttachment' => false
        };

        List<Quote> quotes = [
            SELECT Id, Status
            FROM Quote
            WHERE OpportunityId = :oppId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (quotes.isEmpty()) {
            return status;
        }

        Quote q = quotes[0];
        status.put('quoteExists', true);

        // 라인 아이템 확인
        List<QuoteLineItem> items = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1];
        status.put('hasLineItems', !items.isEmpty());

        // 수락 판정: 협상 단계로 진행하려면 고객이 명시적으로 수락한 상태여야.
        status.put('isAccepted', q.Status == '수락' || q.Status == 'Accepted');

        // 첨부 파일 1건 이상 (D33 — 견적서 PDF 또는 수동 업로드)
        Integer attCount = [
            SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :q.Id
        ];
        status.put('hasAttachment', attCount > 0);

        return status;
    }

    /** 단계별 다음 stage 매핑. terminal(수주/실주)은 자기 자신 반환 → LWC 가 버튼 비활성화. */
    @TestVisible
    private static String nextStage(String fromStage) {
        if (fromStage == STAGE_DISCOVERY) return STAGE_QUOTE_BUILDING;
        if (fromStage == STAGE_QUOTE_BUILDING) return STAGE_QUOTE_SENT;
        if (fromStage == STAGE_QUOTE_SENT) return STAGE_NEGOTIATION;
        if (fromStage == STAGE_NEGOTIATION) return STAGE_WON;
        return fromStage; // 수주/실주/매핑 없음 → terminal
    }

    private static Boolean isAllSatisfied(List<GateRule> rules) {
        for (GateRule g : rules) if (!g.satisfied) return false;
        return true;
    }
}
