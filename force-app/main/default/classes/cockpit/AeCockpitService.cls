/**
 * AeCockpitService — AE 콕피트 5카드 통합 데이터 (Day 9 #6, FR-COCKPIT-001 §1).
 *
 *  5카드:
 *   1) newRfqs        — 최근 7일 신규 Lead (Created DESC)
 *   2) priorityLeads  — Status=신규/제안대기, Lead_Score 내림차순
 *   3) sentQuotes     — Status=발송/응답대기, 발송일 표시 + 열람 여부
 *   4) riskyOrders    — Delivery_Risk_Score>=70, 내림차순
 *   5) arActions      — Long_Term_Debtor=true OR Total_AR>임계, 미수금 내림차순
 *
 * @group Cockpit
 */
public with sharing class AeCockpitService {

    @TestVisible private static final Integer ROW_LIMIT = 10;
    @TestVisible private static final Decimal AR_THRESHOLD = 5000000; // 500만원

    @AuraEnabled(cacheable=true)
    public static Dashboard load() {
        Dashboard d = new Dashboard();
        d.newRfqs       = fetchNewRfqs();
        d.priorityLeads = fetchPriorityLeads();
        d.sentQuotes    = fetchSentQuotes();
        d.riskyOrders   = fetchRiskyOrders();
        d.arActions     = fetchArActions();
        d.stagePipeline = fetchStagePipeline();
        return d;
    }

    /** D35 — Opp Stage 별 건수·금액 집계 (5단계, 실주 제외). */
    @TestVisible
    private static List<PipelineStage> fetchStagePipeline() {
        Map<String, Integer> stageOrder = new Map<String, Integer>{
            '발굴' => 1, '견적 작성' => 2, '견적 발송' => 3, '협상' => 4, '수주' => 5
        };
        Map<String, PipelineStage> byStage = new Map<String, PipelineStage>();
        for (AggregateResult ar : [
            SELECT StageName s, COUNT(Id) cnt, SUM(Amount) amt
            FROM Opportunity
            WHERE IsClosed = false AND StageName != null
            GROUP BY StageName
        ]) {
            String s = (String) ar.get('s');
            if (!stageOrder.containsKey(s)) continue;
            PipelineStage p = new PipelineStage();
            p.stageName   = s;
            p.oppCount    = ((Decimal) ar.get('cnt')).intValue();
            Decimal amt   = (Decimal) ar.get('amt');
            p.totalAmount = (amt == null) ? 0 : amt;
            p.stageOrder  = stageOrder.get(s);
            byStage.put(s, p);
        }
        // 수주 단계는 IsClosed=true 라 위 query 에서 제외됨 — 별도 집계 (Won=true 만)
        for (AggregateResult ar : [
            SELECT COUNT(Id) cnt, SUM(Amount) amt
            FROM Opportunity
            WHERE StageName = '수주' AND IsWon = true
        ]) {
            PipelineStage p = new PipelineStage();
            p.stageName   = '수주';
            p.oppCount    = ((Decimal) ar.get('cnt')).intValue();
            Decimal amt   = (Decimal) ar.get('amt');
            p.totalAmount = (amt == null) ? 0 : amt;
            p.stageOrder  = 5;
            byStage.put('수주', p);
        }
        // 각 단계 보장 (없으면 0)
        List<PipelineStage> out = new List<PipelineStage>();
        for (String s : new List<String>{'발굴','견적 작성','견적 발송','협상','수주'}) {
            if (byStage.containsKey(s)) {
                out.add(byStage.get(s));
            } else {
                PipelineStage z = new PipelineStage();
                z.stageName   = s;
                z.oppCount    = 0;
                z.totalAmount = 0;
                z.stageOrder  = stageOrder.get(s);
                out.add(z);
            }
        }
        return out;
    }

    // ─────────────────────────────────────────────────────────────────────
    // private fetchers
    // ─────────────────────────────────────────────────────────────────────

    private static List<RfqRow> fetchNewRfqs() {
        DateTime cutoff = DateTime.now().addDays(-7);
        List<RfqRow> out = new List<RfqRow>();
        for (Lead l : [
            SELECT Id, Name, Company, Source_Channel__c, Lead_Score__c, CreatedDate, Status
            FROM Lead
            WHERE CreatedDate >= :cutoff
              AND Status = '신규'
              AND IsConverted = false
            ORDER BY CreatedDate DESC
            LIMIT :ROW_LIMIT
        ]) {
            RfqRow r = new RfqRow();
            r.leadId        = l.Id;
            r.leadName      = l.Name;
            r.company       = l.Company;
            r.sourceChannel = l.Source_Channel__c;
            r.leadScore     = nzInt(l.Lead_Score__c);
            r.createdDate   = l.CreatedDate;
            out.add(r);
        }
        return out;
    }

    private static List<LeadRow> fetchPriorityLeads() {
        List<LeadRow> out = new List<LeadRow>();
        for (Lead l : [
            SELECT Id, Name, Company, Lead_Score__c, Status, Source_Channel__c
            FROM Lead
            WHERE Status IN ('신규', '제안대기')
              AND IsConverted = false
              AND Lead_Score__c != null
            ORDER BY Lead_Score__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :ROW_LIMIT
        ]) {
            LeadRow r = new LeadRow();
            r.leadId        = l.Id;
            r.leadName      = l.Name;
            r.company       = l.Company;
            r.leadScore     = nzInt(l.Lead_Score__c);
            r.status        = l.Status;
            r.sourceChannel = l.Source_Channel__c;
            out.add(r);
        }
        return out;
    }

    private static List<QuoteRow> fetchSentQuotes() {
        List<QuoteRow> out = new List<QuoteRow>();
        for (Quote q : [
            SELECT Id, Name, Status, Sent_Date__c, Last_Opened_At__c, Last_Clicked_At__c,
                   Opportunity.Account.Name
            FROM Quote
            WHERE Status IN ('발송', '응답대기')
            ORDER BY Sent_Date__c DESC NULLS LAST
            LIMIT :ROW_LIMIT
        ]) {
            QuoteRow r = new QuoteRow();
            r.quoteId       = q.Id;
            r.quoteName     = q.Name;
            r.accountName   = (q.Opportunity != null && q.Opportunity.Account != null)
                                ? q.Opportunity.Account.Name : '';
            r.status        = q.Status;
            r.sentDate      = q.Sent_Date__c;
            r.lastOpenedAt  = q.Last_Opened_At__c;
            r.lastClickedAt = q.Last_Clicked_At__c;
            r.opened        = q.Last_Opened_At__c != null;
            out.add(r);
        }
        return out;
    }

    private static List<RiskyOrderRow> fetchRiskyOrders() {
        List<RiskyOrderRow> out = new List<RiskyOrderRow>();
        for (Order o : [
            SELECT Id, Name, PoNumber, Production_Status__c, Delivery_Risk_Score__c,
                   Last_ErpSync_At__c, EndDate, Account.Name
            FROM Order
            WHERE Delivery_Risk_Score__c >= 70
            ORDER BY Delivery_Risk_Score__c DESC
            LIMIT :ROW_LIMIT
        ]) {
            RiskyOrderRow r = new RiskyOrderRow();
            r.orderId          = o.Id;
            r.orderName        = o.Name;
            r.poNumber         = o.PoNumber;
            r.accountName      = (o.Account != null) ? o.Account.Name : '';
            r.productionStatus = o.Production_Status__c;
            r.riskScore        = nzInt(o.Delivery_Risk_Score__c);
            r.lastErpSyncAt    = o.Last_ErpSync_At__c;
            r.endDate          = o.EndDate;
            r.dueLabel         = dueLabel(o.EndDate);
            out.add(r);
        }
        return out;
    }

    /** D33 — Order.EndDate 기준 한국어 D-N / OVERDUE 라벨. */
    @TestVisible
    public static String dueLabel(Date endDate) {
        if (endDate == null) return '';
        Integer days = Date.today().daysBetween(endDate);
        if (days < 0)  return '⚠ D+' + Math.abs(days) + ' 초과';
        if (days == 0) return '⏰ D-day';
        if (days <= 3) return '🔥 D-' + days;
        return 'D-' + days;
    }

    private static List<ArRow> fetchArActions() {
        List<ArRow> out = new List<ArRow>();
        for (Account a : [
            SELECT Id, Name, Total_AR__c, Long_Term_Debtor__c, Credit_Limit__c
            FROM Account
            WHERE Long_Term_Debtor__c = true OR Total_AR__c >= :AR_THRESHOLD
            ORDER BY Total_AR__c DESC NULLS LAST
            LIMIT :ROW_LIMIT
        ]) {
            ArRow r = new ArRow();
            r.accountId    = a.Id;
            r.accountName  = a.Name;
            r.totalAR      = a.Total_AR__c == null ? 0 : a.Total_AR__c;
            r.creditLimit  = a.Credit_Limit__c == null ? 0 : a.Credit_Limit__c;
            r.isLongTerm   = a.Long_Term_Debtor__c == true;
            out.add(r);
        }
        return out;
    }

    private static Integer nzInt(Decimal v) {
        return v == null ? 0 : Integer.valueOf(v);
    }

    // ─────────────────────────────────────────────────────────────────────
    // DTOs
    // ─────────────────────────────────────────────────────────────────────

    public class Dashboard {
        @AuraEnabled public List<RfqRow>        newRfqs;
        @AuraEnabled public List<LeadRow>       priorityLeads;
        @AuraEnabled public List<QuoteRow>      sentQuotes;
        @AuraEnabled public List<RiskyOrderRow> riskyOrders;
        @AuraEnabled public List<ArRow>         arActions;
        @AuraEnabled public List<PipelineStage> stagePipeline;
    }

    public class PipelineStage {
        @AuraEnabled public String stageName;
        @AuraEnabled public Integer oppCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Integer stageOrder;
    }

    public class RfqRow {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String company;
        @AuraEnabled public String sourceChannel;
        @AuraEnabled public Integer leadScore;
        @AuraEnabled public DateTime createdDate;
    }

    public class LeadRow {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String company;
        @AuraEnabled public Integer leadScore;
        @AuraEnabled public String status;
        @AuraEnabled public String sourceChannel;
    }

    public class QuoteRow {
        @AuraEnabled public Id quoteId;
        @AuraEnabled public String quoteName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime sentDate;
        @AuraEnabled public DateTime lastOpenedAt;
        @AuraEnabled public DateTime lastClickedAt;
        @AuraEnabled public Boolean opened;
    }

    public class RiskyOrderRow {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderName;
        @AuraEnabled public String poNumber;
        @AuraEnabled public String accountName;
        @AuraEnabled public String productionStatus;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public DateTime lastErpSyncAt;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String dueLabel;
    }

    public class ArRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal totalAR;
        @AuraEnabled public Decimal creditLimit;
        @AuraEnabled public Boolean isLongTerm;
    }
}
