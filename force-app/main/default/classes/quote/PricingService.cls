/**
 * PricingService — Quote 라인 편집 + 합계 계산 진입점.
 *
 * Apex 책임:
 *   - getQuoteSummary(quoteId): 헤더 + 라인 + 합계(Subtotal/TotalDiscount/NetTotal) 반환
 *   - updateLine(qliId, qty, unitPrice, discountAmount): 라인 업데이트 + Quote.AE_Edit_Count__c +1
 *   - addLine(quoteId, productId, qty): Quote.Pricebook2Id에서 PricebookEntry 찾아 QLI 생성
 *   - deleteLine(qliId): 라인 삭제 + 편집 카운트 증가
 *
 * Discount_Percent__c는 formula 필드 (Discount_Amount / (UnitPrice * Quantity)) — 자동 계산.
 *
 * @group Quote
 */
public with sharing class PricingService {

    // ─────────────────────────────────────────────────────────────────────
    // Public API (LWC)
    // ─────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static QuoteSummaryDTO getQuoteSummary(Id quoteId) {
        if (quoteId == null) {
            throw newAuraException('quoteId is required');
        }
        return loadSummary(quoteId);
    }

    /**
     * Quote의 Pricebook에 등록된 활성 Product 목록 — 라인 추가 모달의 검색 옵션.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductOptionDTO> getActiveProducts(Id quoteId) {
        if (quoteId == null) throw newAuraException('quoteId is required');
        Quote q = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
        if (q.Pricebook2Id == null) return new List<ProductOptionDTO>();

        List<ProductOptionDTO> out = new List<ProductOptionDTO>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, Product2.Name, Product2.ProductCode, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :q.Pricebook2Id AND IsActive = true AND Product2.IsActive = true
            ORDER BY Product2.Name ASC
            LIMIT 200
        ]) {
            ProductOptionDTO p = new ProductOptionDTO();
            p.productId   = pbe.Product2Id;
            p.productName = pbe.Product2.Name;
            p.productCode = pbe.Product2.ProductCode;
            p.unitPrice   = pbe.UnitPrice;
            out.add(p);
        }
        return out;
    }

    @AuraEnabled
    public static QuoteSummaryDTO updateLine(
        Id qliId, Decimal quantity, Decimal unitPrice, Decimal discountAmount
    ) {
        if (qliId == null) throw newAuraException('qliId is required');

        QuoteLineItem qli = [
            SELECT Id, QuoteId, Quantity, UnitPrice, Discount_Amount__c
            FROM QuoteLineItem WHERE Id = :qliId LIMIT 1
        ];
        if (quantity != null)        qli.Quantity = quantity;
        if (unitPrice != null)       qli.UnitPrice = unitPrice;
        if (discountAmount != null)  qli.Discount_Amount__c = discountAmount;

        try {
            update qli;
            incrementEditCount(qli.QuoteId);
        } catch (DmlException e) {
            throw newAuraException('라인 업데이트 실패: ' + e.getDmlMessage(0));
        }
        return loadSummary(qli.QuoteId);
    }

    @AuraEnabled
    public static QuoteSummaryDTO addLine(Id quoteId, Id productId, Decimal quantity) {
        if (quoteId == null)   throw newAuraException('quoteId is required');
        if (productId == null) throw newAuraException('productId is required');

        Quote q = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
        if (q.Pricebook2Id == null) {
            throw newAuraException('Quote에 Price Book이 지정돼있지 않습니다.');
        }

        List<PricebookEntry> entries = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id = :productId AND Pricebook2Id = :q.Pricebook2Id AND IsActive = true
            LIMIT 1
        ];
        if (entries.isEmpty()) {
            throw newAuraException('Product가 Quote의 Price Book에 등록되지 않았습니다.');
        }

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId          = quoteId,
            PricebookEntryId = entries[0].Id,
            Product2Id       = productId,
            Quantity         = quantity == null ? 1 : quantity,
            UnitPrice        = entries[0].UnitPrice,
            Discount_Amount__c = 0
        );
        try {
            insert qli;
            incrementEditCount(quoteId);
        } catch (DmlException e) {
            throw newAuraException('라인 추가 실패: ' + e.getDmlMessage(0));
        }
        return loadSummary(quoteId);
    }

    @AuraEnabled
    public static QuoteSummaryDTO deleteLine(Id qliId) {
        if (qliId == null) throw newAuraException('qliId is required');

        QuoteLineItem qli = [SELECT Id, QuoteId FROM QuoteLineItem WHERE Id = :qliId LIMIT 1];
        Id quoteId = qli.QuoteId;
        try {
            delete qli;
            incrementEditCount(quoteId);
        } catch (DmlException e) {
            throw newAuraException('라인 삭제 실패: ' + e.getDmlMessage(0));
        }
        return loadSummary(quoteId);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static void incrementEditCount(Id quoteId) {
        Quote q = [SELECT Id, AE_Edit_Count__c FROM Quote WHERE Id = :quoteId LIMIT 1];
        Decimal current = (q.AE_Edit_Count__c == null ? 0 : q.AE_Edit_Count__c);
        q.AE_Edit_Count__c = current + 1;
        update q;
    }

    private static QuoteSummaryDTO loadSummary(Id quoteId) {
        Quote q = [
            SELECT Id, Name, Status, ExpirationDate, AE_Edit_Count__c, AI_Draft_Confidence__c,
                   Account.Name, Account.Total_AR__c, Account.Long_Term_Debtor__c,
                   Account.Credit_Limit__c,
                   Opportunity.Name, Pricebook2Id,
                   (SELECT Id, Quantity, UnitPrice, Discount_Amount__c, Discount_Percent__c,
                           Product2Id, Product2.Name, Product2.ProductCode
                    FROM QuoteLineItems
                    ORDER BY CreatedDate ASC)
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];

        QuoteSummaryDTO out = new QuoteSummaryDTO();
        out.header = headerOf(q);
        out.lines = new List<LineDTO>();
        Decimal subtotal = 0, totalDiscount = 0;
        for (QuoteLineItem qli : q.QuoteLineItems) {
            LineDTO ld = lineOf(qli);
            out.lines.add(ld);
            subtotal      += (ld.lineSubtotal != null ? ld.lineSubtotal : 0);
            totalDiscount += (ld.discountAmount != null ? ld.discountAmount : 0);
        }
        out.summary = new SummaryDTO();
        out.summary.subtotal      = subtotal;
        out.summary.totalDiscount = totalDiscount;
        out.summary.netTotal      = subtotal - totalDiscount;
        out.summary.lineCount     = out.lines.size();

        // FR-AR-003 — 신용한도 가시화: Total_AR + 견적 금액 이 Credit_Limit 초과 시 경고 플래그.
        // 단순 표시(차단 X — D8 NG-012 일관, 사용자는 결정만 보고 AE 결정).
        if (out.header.creditLimit != null && out.header.creditLimit > 0) {
            Decimal exposure = (out.header.totalAR == null ? 0 : out.header.totalAR) + out.summary.netTotal;
            out.header.creditExceeded = exposure > out.header.creditLimit;
            out.header.creditUtilization = exposure;
        }
        return out;
    }

    private static QuoteHeaderDTO headerOf(Quote q) {
        QuoteHeaderDTO h = new QuoteHeaderDTO();
        h.id                 = q.Id;
        h.name               = q.Name;
        h.status             = q.Status;
        h.expirationDate     = q.ExpirationDate;
        h.aeEditCount        = q.AE_Edit_Count__c;
        h.aiDraftConfidence  = q.AI_Draft_Confidence__c;
        h.accountName        = q.Account != null ? q.Account.Name : null;
        h.opportunityName    = q.Opportunity != null ? q.Opportunity.Name : null;
        // FR-AR-003 — 헤더에 AR 상황 노출 (Total_AR / Long_Term_Debtor / Credit_Limit)
        h.totalAR            = q.Account != null ? q.Account.Total_AR__c : null;
        h.longTermDebtor     = q.Account != null && q.Account.Long_Term_Debtor__c == true;
        h.creditLimit        = q.Account != null ? q.Account.Credit_Limit__c : null;
        h.creditExceeded     = false;  // loadSummary 에서 netTotal 후 재계산
        h.creditUtilization  = null;
        return h;
    }

    private static LineDTO lineOf(QuoteLineItem qli) {
        LineDTO ld = new LineDTO();
        ld.id              = qli.Id;
        ld.productId       = qli.Product2Id;
        ld.productName     = qli.Product2 != null ? qli.Product2.Name : null;
        ld.productCode     = qli.Product2 != null ? qli.Product2.ProductCode : null;
        ld.quantity        = qli.Quantity;
        ld.unitPrice       = qli.UnitPrice;
        ld.discountAmount  = qli.Discount_Amount__c;
        ld.discountPercent = qli.Discount_Percent__c;
        Decimal qty   = qli.Quantity != null ? qli.Quantity : 0;
        Decimal price = qli.UnitPrice != null ? qli.UnitPrice : 0;
        Decimal disc  = qli.Discount_Amount__c != null ? qli.Discount_Amount__c : 0;
        ld.lineSubtotal = qty * price;
        ld.lineNetTotal = (qty * price) - disc;
        return ld;
    }

    private static AuraHandledException newAuraException(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs
    // ─────────────────────────────────────────────────────────────────────

    public class QuoteSummaryDTO {
        @AuraEnabled public QuoteHeaderDTO header;
        @AuraEnabled public List<LineDTO> lines;
        @AuraEnabled public SummaryDTO summary;
    }

    public class QuoteHeaderDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Date expirationDate;
        @AuraEnabled public Decimal aeEditCount;
        @AuraEnabled public Decimal aiDraftConfidence;
        // FR-AR-003
        @AuraEnabled public Decimal totalAR;
        @AuraEnabled public Boolean longTermDebtor;
        @AuraEnabled public Decimal creditLimit;
        @AuraEnabled public Boolean creditExceeded;
        @AuraEnabled public Decimal creditUtilization;
    }

    public class LineDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal discountAmount;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Decimal lineSubtotal;
        @AuraEnabled public Decimal lineNetTotal;
    }

    public class SummaryDTO {
        @AuraEnabled public Decimal subtotal;
        @AuraEnabled public Decimal totalDiscount;
        @AuraEnabled public Decimal netTotal;
        @AuraEnabled public Integer lineCount;
    }

    public class ProductOptionDTO {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal unitPrice;
    }
}
