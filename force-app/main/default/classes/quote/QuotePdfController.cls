/**
 * QuotePdfController — 한도정밀 견적서 (한국 시나리오 데이터 매핑).
 *
 * 우리 데이터 매핑:
 *   - Account.Business_Number__c, CEO_Name__c, BillingStreet → 수신처
 *   - Quote.Owner.Name/Email/Phone → AE 담당자
 *   - Quote.AE_Edit_Count__c, AI_Draft_Confidence__c → 편집 흔적
 *   - Opportunity.Name/StageName → 거래 개요
 *   - QuoteLineItem.Discount_Amount__c → 라인별 할인 (formula로 % 자동)
 */
public with sharing class QuotePdfController {

    public Quote quote { get; set; }
    public List<LineRow> lines { get; set; }
    public Decimal subtotal { get; set; }
    public Decimal totalDiscount { get; set; }
    public Decimal taxAmount { get; set; }
    public Decimal netTotal { get; set; }
    public Decimal grandTotal { get; set; }
    public String netTotalKorean { get; set; }

    public String quoteNumber { get; set; }

    // 수신 (고객사) — 한국 견적서 표준 필드
    public String accountName { get; set; }
    public String accountBizNumber { get; set; }
    public String accountCEO { get; set; }
    public String accountAddress { get; set; }
    public String accountPhone { get; set; }

    // 거래 개요
    public String opportunityName { get; set; }
    public String opportunityStage { get; set; }
    public String statusLabel { get; set; }
    public Decimal aeEditCount { get; set; }

    // AE 담당자
    public String aeName { get; set; }
    public String aeEmail { get; set; }
    public String aePhone { get; set; }

    // 비고
    public String descriptionHtml { get; set; }
    public Boolean hasDescription { get; set; }
    public Boolean hasNoLines { get; set; }

    // 발신 (한도정밀) 브랜딩
    public String brandCompany { get; set; }
    public String brandSubtitle { get; set; }
    public String brandRegNumber { get; set; }
    public String brandCEO { get; set; }
    public String brandAddress { get; set; }
    public String brandPhone { get; set; }
    public String brandEmail { get; set; }

    public QuotePdfController(ApexPages.StandardController stdCtrl) {
        loadBrand();
        Id quoteId = stdCtrl.getId();
        loadQuote(quoteId);
        loadLines(quoteId);
    }

    private void loadBrand() {
        brandCompany   = '한 도 정 밀';
        brandSubtitle  = '정밀가공·산업기계 제조 전문기업';
        brandRegNumber = '100-00-00009';
        brandCEO       = '이 재 용';
        brandAddress   = '경기도 안산시 단원구 산단로 123';
        brandPhone     = '031-XXX-XXXX';
        brandEmail     = 'sales@hando.co.kr';
    }

    private void loadQuote(Id quoteId) {
        quote = [
            SELECT Id, Name, QuoteNumber, Status, ExpirationDate, Description,
                   Tax, AE_Edit_Count__c,
                   Account.Name, Account.Business_Number__c, Account.CEO_Name__c,
                   Account.BillingStreet, Account.BillingCity, Account.BillingState,
                   Account.BillingPostalCode, Account.Phone,
                   Opportunity.Name, Opportunity.StageName,
                   Owner.Name, Owner.Email, Owner.Phone
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];

        quoteNumber       = String.isBlank(quote.QuoteNumber) ? quote.Name : quote.QuoteNumber;

        accountName       = quote.Account != null ? blankAsDash(quote.Account.Name) : '-';
        accountBizNumber  = quote.Account != null ? blankAsDash(quote.Account.Business_Number__c) : '-';
        accountCEO        = quote.Account != null ? blankAsDash(quote.Account.CEO_Name__c) : '-';
        accountAddress    = formatAccountAddress(quote.Account);
        accountPhone      = quote.Account != null ? blankAsDash(quote.Account.Phone) : '-';

        opportunityName   = quote.Opportunity != null ? blankAsDash(quote.Opportunity.Name) : '-';
        opportunityStage  = quote.Opportunity != null ? blankAsDash(quote.Opportunity.StageName) : '-';
        statusLabel       = blankAsDash(quote.Status);
        aeEditCount       = quote.AE_Edit_Count__c != null ? quote.AE_Edit_Count__c : 0;

        aeName            = quote.Owner != null ? blankAsDash(quote.Owner.Name) : '-';
        aeEmail           = quote.Owner != null ? blankAsDash(quote.Owner.Email) : '-';
        aePhone           = quote.Owner != null ? blankAsDash(quote.Owner.Phone) : '-';

        hasDescription    = !String.isBlank(quote.Description);
        descriptionHtml   = hasDescription ? quote.Description.escapeHtml4().replace('\n', '<br/>') : '';
        taxAmount         = quote.Tax != null ? quote.Tax : 0;
    }

    private void loadLines(Id quoteId) {
        List<QuoteLineItem> qlis = [
            SELECT Id, Quantity, UnitPrice, Discount_Amount__c,
                   Product2.Name, Product2.ProductCode
            FROM QuoteLineItem WHERE QuoteId = :quoteId ORDER BY CreatedDate ASC
        ];

        lines = new List<LineRow>();
        Decimal sub = 0, disc = 0;
        Integer idx = 1;
        for (QuoteLineItem qli : qlis) {
            LineRow r = new LineRow();
            r.seq            = idx++;
            r.productName    = qli.Product2 != null ? qli.Product2.Name : '-';
            r.productCode    = qli.Product2 != null ? blankAsDash(qli.Product2.ProductCode) : '-';
            Decimal qty   = qli.Quantity != null ? qli.Quantity : 0;
            Decimal price = qli.UnitPrice != null ? qli.UnitPrice : 0;
            Decimal d     = qli.Discount_Amount__c != null ? qli.Discount_Amount__c : 0;
            r.quantity       = qty;
            r.unitPrice      = price;
            r.discountAmount = d;
            r.lineNetTotal   = qty * price - d;
            lines.add(r);
            sub  += qty * price;
            disc += d;
        }
        subtotal       = sub;
        totalDiscount  = disc;
        netTotal       = sub - disc;
        grandTotal     = netTotal + (taxAmount != null ? taxAmount : 0);
        netTotalKorean = toKoreanAmount(grandTotal);
        hasNoLines     = lines.isEmpty();
    }

    private static String blankAsDash(String v) {
        return String.isBlank(v) ? '-' : v;
    }

    private static String formatAccountAddress(Account acc) {
        if (acc == null) return '-';
        List<String> parts = new List<String>();
        if (!String.isBlank(acc.BillingPostalCode)) parts.add('(' + acc.BillingPostalCode + ')');
        List<String> citySt = new List<String>();
        if (!String.isBlank(acc.BillingState)) citySt.add(acc.BillingState);
        if (!String.isBlank(acc.BillingCity))  citySt.add(acc.BillingCity);
        if (!citySt.isEmpty()) parts.add(String.join(citySt, ' '));
        if (!String.isBlank(acc.BillingStreet)) parts.add(acc.BillingStreet);
        return parts.isEmpty() ? '-' : String.join(parts, ' ');
    }

    public static String toKoreanAmount(Decimal amount) {
        if (amount == null || amount <= 0) return '일금 영원정';
        Long n = amount.longValue();
        String[] digits = new String[]{ '', '일', '이', '삼', '사', '오', '육', '칠', '팔', '구' };
        String[] pos    = new String[]{ '', '십', '백', '천' };
        String[] big    = new String[]{ '', '만', '억', '조' };

        String result = '';
        Integer bigIdx = 0;
        while (n > 0 && bigIdx < big.size()) {
            Long chunkL = Math.mod(n, 10000);
            if (chunkL > 0) {
                String chunkKor = '';
                Integer p = 0;
                Long c = chunkL;
                while (c > 0) {
                    Integer d = (Integer)(c - (c / 10) * 10);
                    if (d > 0) chunkKor = digits[d] + pos[p] + chunkKor;
                    c = c / 10;
                    p++;
                }
                result = chunkKor + big[bigIdx] + result;
            }
            n = n / 10000;
            bigIdx++;
        }
        return '일금 ' + result + '원정';
    }

    public class LineRow {
        public Integer seq            { get; set; }
        public String  productName    { get; set; }
        public String  productCode    { get; set; }
        public Decimal quantity       { get; set; }
        public Decimal unitPrice      { get; set; }
        public Decimal discountAmount { get; set; }
        public Decimal lineNetTotal   { get; set; }
    }
}
