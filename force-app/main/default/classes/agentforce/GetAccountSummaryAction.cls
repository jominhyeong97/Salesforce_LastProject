/**
 * GetAccountSummaryAction — Agentforce Action: Account 360 요약.
 *
 * 한도정밀 영업 핵심 6 필드 + 진행중 Opp/Order 건수 + 미수금 통계 반환.
 *  - Account: Business_Number__c / CEO_Name__c / Credit_Limit__c
 *             / External_Credit_Score__c / Total_AR__c / Long_Term_Debtor__c
 *  - 집계: 진행중 Opp 건수 / 미출고 Order 건수 / 장기미수 Payment 건수
 *
 * 입력: accountId(우선) 또는 accountName(부분 일치 1건 매칭).
 *
 * 사용 시점 — "한도정밀의 미수금", "○○ 고객사 정보", "신용한도" 등.
 *
 * @group Agentforce
 */
public with sharing class GetAccountSummaryAction {

    public class Request {
        @InvocableVariable(
            label='Account ID'
            description='Salesforce Account 18-char Id. accountName 보다 우선.'
            required=false
        )
        public Id accountId;

        @InvocableVariable(
            label='Account 이름'
            description='Account.Name 부분 일치(첫 1건 사용). accountId 가 없을 때만 사용.'
            required=false
        )
        public String accountName;
    }

    public class Response {
        @InvocableVariable(label='한국어 요약')
        public String summary;

        @InvocableVariable(label='Account ID')
        public Id accountId;

        @InvocableVariable(label='Account 이름')
        public String accountName;

        @InvocableVariable(label='사업자번호')
        public String businessNumber;

        @InvocableVariable(label='대표자')
        public String ceoName;

        @InvocableVariable(label='신용한도(원)')
        public Decimal creditLimit;

        @InvocableVariable(label='외부 신용점수')
        public Decimal externalCreditScore;

        @InvocableVariable(label='누적 미수금(원)')
        public Decimal totalAR;

        @InvocableVariable(label='장기미수 보유')
        public Boolean longTermDebtor;

        @InvocableVariable(label='진행중 Opp 건수')
        public Integer openOppCount;

        @InvocableVariable(label='미출고 Order 건수')
        public Integer openOrderCount;

        @InvocableVariable(label='발견 여부')
        public Boolean found;
    }

    @InvocableMethod(
        label='Get Account Summary'
        description='Account 한 곳의 영업 360 요약을 반환합니다. 사업자번호/대표자/신용한도/외부신용점수/누적미수금/장기미수 여부, 진행중 Opp·Order 건수.'
        category='Sales Cockpit'
    )
    public static List<Response> run(List<Request> reqs) {
        Request req = (reqs != null && !reqs.isEmpty()) ? reqs[0] : new Request();

        Account a = findAccount(req);
        Response r = new Response();
        if (a == null) {
            r.found = false;
            r.summary = '일치하는 Account 를 찾지 못했습니다.';
            return new List<Response>{ r };
        }

        Integer openOpps = [
            SELECT COUNT() FROM Opportunity
            WHERE AccountId = :a.Id AND IsClosed = false
        ];
        Integer openOrders = [
            SELECT COUNT() FROM Order
            WHERE AccountId = :a.Id
              AND Production_Status__c IN ('InProgress', 'Pending', 'Done')
        ];

        r.found               = true;
        r.accountId           = a.Id;
        r.accountName         = a.Name;
        r.businessNumber      = a.Business_Number__c;
        r.ceoName             = a.CEO_Name__c;
        r.creditLimit         = a.Credit_Limit__c;
        r.externalCreditScore = a.External_Credit_Score__c;
        r.totalAR             = a.Total_AR__c == null ? 0 : a.Total_AR__c;
        r.longTermDebtor      = a.Long_Term_Debtor__c == true;
        r.openOppCount        = openOpps;
        r.openOrderCount      = openOrders;
        r.summary             = buildSummary(r);

        return new List<Response>{ r };
    }

    private static Account findAccount(Request req) {
        if (req.accountId != null) {
            List<Account> byId = [
                SELECT Id, Name, Business_Number__c, CEO_Name__c, Credit_Limit__c,
                       External_Credit_Score__c, Total_AR__c, Long_Term_Debtor__c
                FROM Account WHERE Id = :req.accountId LIMIT 1
            ];
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isNotBlank(req.accountName)) {
            String namePattern = '%' + req.accountName.trim() + '%';
            List<Account> byName = [
                SELECT Id, Name, Business_Number__c, CEO_Name__c, Credit_Limit__c,
                       External_Credit_Score__c, Total_AR__c, Long_Term_Debtor__c
                FROM Account WHERE Name LIKE :namePattern
                ORDER BY Total_AR__c DESC NULLS LAST
                LIMIT 1
            ];
            return byName.isEmpty() ? null : byName[0];
        }
        return null;
    }

    @TestVisible
    private static String buildSummary(Response r) {
        List<String> parts = new List<String>();
        parts.add(r.accountName + ' — 사업자번호 ' + (String.isBlank(r.businessNumber) ? '미상' : r.businessNumber));
        if (String.isNotBlank(r.ceoName)) parts.add('대표자 ' + r.ceoName);
        if (r.externalCreditScore != null) parts.add('외부 신용점수 ' + Integer.valueOf(r.externalCreditScore));
        if (r.creditLimit != null && r.creditLimit > 0) parts.add('신용한도 ' + r.creditLimit.format() + '원');
        if (r.totalAR != null && r.totalAR > 0) parts.add('누적 미수금 ' + r.totalAR.format() + '원');
        if (r.longTermDebtor == true) parts.add('⚠️ 장기미수 보유');
        parts.add('진행중 Opp ' + r.openOppCount + '건 / 미출고 Order ' + r.openOrderCount + '건');
        return String.join(parts, ' · ');
    }
}
