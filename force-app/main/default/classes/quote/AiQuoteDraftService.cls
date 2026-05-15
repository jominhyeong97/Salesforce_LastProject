/**
 * AiQuoteDraftService — Opportunity → AI Quote 초안 자동 생성 (FR-QUOTE-001).
 *
 * 흐름:
 *   1. Opp.Description (또는 RFQ_Spec_JSON) 파싱
 *   2. 카탈로그(활성 Product)에서 키워드 매칭 → Top 1 SKU 선정 + confidence
 *   3. Quote(Status=초안) + QuoteLineItem 자동 생성
 *   4. AI_Draft_Confidence__c 기록 → Quote ID 반환 (5초 이내)
 *
 * Day 8/9 업그레이드: Apex 매칭 → Prompt Builder SkuMatch 멀티 SKU 버전.
 */
public with sharing class AiQuoteDraftService {

    @AuraEnabled
    public static AiDraftResult generateAiQuote(Id opportunityId) {
        if (opportunityId == null) throw newAura('opportunityId is required');

        Opportunity opp = [
            SELECT Id, Name, AccountId, Description, StageName, CloseDate
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opp.AccountId == null) {
            throw newAura('Opportunity에 Account가 연결돼있지 않습니다.');
        }

        // 1. RFQ 사양 파싱
        SpecParseResult spec = parseSpec(opp.Description);

        // 2. 카탈로그 매칭 (키워드 contains + 부분일치 confidence)
        Id stdPbId;
        if (Test.isRunningTest()) {
            stdPbId = Test.getStandardPricebookId();
        } else {
            stdPbId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
        }
        MatchResult best = matchProducts(spec, stdPbId);
        if (best == null) {
            throw newAura('카탈로그에서 매칭 가능한 제품을 찾지 못했습니다. 활성 Product와 PricebookEntry를 확인하세요.');
        }

        // 3. Quote 생성
        Quote q = new Quote(
            Name           = buildQuoteName(opp),
            OpportunityId  = opp.Id,
            Pricebook2Id   = stdPbId,
            Status         = '초안',
            ExpirationDate = Date.today().addDays(14),
            AI_Draft_Confidence__c = best.confidence,
            AE_Edit_Count__c = 0,
            Description = buildDescription(spec, best)
        );
        try {
            insert q;
        } catch (DmlException e) {
            throw newAura('Quote 생성 실패: ' + e.getDmlMessage(0));
        }

        // 4. QLI 생성 (수량은 spec에서 추출, 없으면 1)
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId          = q.Id,
            PricebookEntryId = best.pbeId,
            Product2Id       = best.productId,
            Quantity         = spec.quantity != null ? spec.quantity : 1,
            UnitPrice        = best.unitPrice,
            Discount_Amount__c = 0
        );
        try {
            insert qli;
        } catch (DmlException e) {
            throw newAura('Quote 라인 생성 실패: ' + e.getDmlMessage(0));
        }

        AiDraftResult out = new AiDraftResult();
        out.quoteId           = q.Id;
        out.quoteName         = q.Name;
        out.matchedProductId  = best.productId;
        out.matchedProductName = best.productName;
        out.confidence        = best.confidence;
        out.matchReason       = best.reason;
        return out;
    }

    // ─────────────────────────────────────────────────────────────────────
    // RFQ 사양 파싱 — JSON 또는 자유 텍스트
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static SpecParseResult parseSpec(String description) {
        SpecParseResult out = new SpecParseResult();
        out.rawText = description == null ? '' : description;

        if (String.isBlank(description)) return out;

        // JSON 시도 (LeadTriggerHandler가 RFQ_Spec_JSON__c를 Description으로 복사한 케이스)
        String trimmed = description.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
            try {
                Object parsed = JSON.deserializeUntyped(trimmed);
                if (parsed instanceof Map<String, Object>) {
                    Map<String, Object> j = (Map<String, Object>) parsed;
                    if (j.get('partName') != null) out.productKeyword = String.valueOf(j.get('partName'));
                    if (j.get('product') != null && out.productKeyword == null) out.productKeyword = String.valueOf(j.get('product'));
                    if (j.get('quantity') != null) {
                        try { out.quantity = Decimal.valueOf(String.valueOf(j.get('quantity'))); } catch (Exception e) {}
                    }
                }
            } catch (Exception e) {
                // JSON 아니면 무시 — 자유 텍스트 fallback
            }
        }

        // 자유 텍스트에서 한글 키워드 추출 (베어링/단조품/믹서 등)
        if (String.isBlank(out.productKeyword)) {
            String[] keywords = new String[]{ '베어링', '단조품', '믹서', '발전기', '클러', '혼합기' };
            for (String kw : keywords) {
                if (description.contains(kw)) {
                    out.productKeyword = kw;
                    break;
                }
            }
        }
        return out;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 카탈로그 매칭 — 키워드 contains, 매칭 강도 → confidence
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static MatchResult matchProducts(SpecParseResult spec, Id pricebookId) {
        List<PricebookEntry> entries = [
            SELECT Id, Product2Id, Product2.Name, Product2.ProductCode, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
                AND IsActive = true AND Product2.IsActive = true
            ORDER BY Product2.Name ASC
            LIMIT 200
        ];
        if (entries.isEmpty()) return null;

        MatchResult best = null;
        for (PricebookEntry pbe : entries) {
            String pname = pbe.Product2 != null && pbe.Product2.Name != null ? pbe.Product2.Name : '';
            Decimal score;
            String reason;

            if (String.isNotBlank(spec.productKeyword) && pname.contains(spec.productKeyword)) {
                score = 0.85;
                reason = '제품명에 "' + spec.productKeyword + '" 키워드 매칭';
            } else if (String.isBlank(spec.productKeyword)) {
                score = 0.50;
                reason = 'RFQ 사양 미상 — 카탈로그 첫 활성 제품 default 매칭';
            } else {
                score = 0.30;
                reason = '키워드 부분 매칭';
            }

            if (best == null || score > best.confidence) {
                best = new MatchResult();
                best.pbeId        = pbe.Id;
                best.productId    = pbe.Product2Id;
                best.productName  = pname;
                best.unitPrice    = pbe.UnitPrice;
                best.confidence   = score;
                best.reason       = reason;
                if (score >= 0.85) break; // 강한 매칭 즉시 채택
            }
        }
        return best;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 헬퍼
    // ─────────────────────────────────────────────────────────────────────

    private static String buildQuoteName(Opportunity opp) {
        String oppPart = (opp.Name != null && opp.Name.length() > 12) ? opp.Name.substring(0, 12) : opp.Name;
        return 'AI-' + (oppPart != null ? oppPart : 'OPP') + '-' + Datetime.now().format('MMddHHmm');
    }

    private static String buildDescription(SpecParseResult spec, MatchResult best) {
        return 'AI 견적 초안 — ' + best.reason +
               ' (신뢰도 ' + best.confidence.setScale(2).toPlainString() + ')\n\n' +
               '※ AE 검토 후 라인/할인을 조정하고 발송하세요.';
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs
    // ─────────────────────────────────────────────────────────────────────

    public class AiDraftResult {
        @AuraEnabled public Id      quoteId;
        @AuraEnabled public String  quoteName;
        @AuraEnabled public Id      matchedProductId;
        @AuraEnabled public String  matchedProductName;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String  matchReason;
    }

    public class SpecParseResult {
        public String  rawText;
        public String  productKeyword;
        public Decimal quantity;
    }

    public class MatchResult {
        public Id      pbeId;
        public Id      productId;
        public String  productName;
        public Decimal unitPrice;
        public Decimal confidence;
        public String  reason;
    }
}
