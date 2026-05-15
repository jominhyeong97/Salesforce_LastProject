/**
 * GetCrossSellCandidatesAction — Agentforce Action: Cross-sell 후보 추천.
 *
 * 알고리즘:
 *   1. 입력 Account 가 과거에 발주한 Product2 의 Family 집합 수집
 *   2. 같은 Family 의 다른 활성 Product2 중 이 고객이 한 번도 발주 안 한 것 선별
 *   3. 전체 Order 의 OrderItem 수 기준 인기 Top 5 반환 (없으면 빈 리스트)
 *
 * 안전 정책 (D26): 가격 새로 제시 X. 후보 Product 정보만 반환, 견적은 AE 가 quoteBuilder 로.
 *
 * 사용 시점 — AE 자연어 질의: "현대모비스에게 뭐 더 팔 수 있을까?", "추천 부품", "교차 판매".
 *
 * @group Agentforce
 */
public with sharing class GetCrossSellCandidatesAction {

    public class Request {
        @InvocableVariable(
            label='Account ID'
            description='Cross-sell 분석 대상 Account 의 18-char Id (필수). accountName 보다 우선.'
            required=false
        )
        public Id accountId;

        @InvocableVariable(
            label='Account 이름'
            description='accountId 없을 때 Account.Name 부분 일치(첫 1건). 둘 다 없으면 발견 실패.'
            required=false
        )
        public String accountName;

        @InvocableVariable(
            label='최대 후보 수'
            description='반환할 후보 Product 최대 개수 (기본 5).'
            required=false
        )
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='한국어 요약')
        public String summary;

        @InvocableVariable(label='Account ID')
        public Id accountId;

        @InvocableVariable(label='Account 이름')
        public String accountName;

        @InvocableVariable(label='후보 건수')
        public Integer candidateCount;

        @InvocableVariable(label='후보 Product JSON')
        public String candidatesJson;

        @InvocableVariable(label='발견 여부')
        public Boolean found;
    }

    @InvocableMethod(
        label='Get Cross Sell Candidates'
        description='특정 Account 의 과거 발주 Product Family 기반으로 같은 Family 내 미구매 Product 추천. 자연어: "교차 판매", "추천 부품", "더 팔 수 있는".'
        category='Sales Cockpit'
    )
    public static List<Response> run(List<Request> reqs) {
        Request req = (reqs != null && !reqs.isEmpty()) ? reqs[0] : new Request();
        Integer cap = (req.maxResults != null && req.maxResults > 0) ? req.maxResults : 5;

        Response r = new Response();
        Account a = findAccount(req);
        if (a == null) {
            r.found = false;
            r.summary = '일치하는 Account 를 찾지 못했습니다.';
            r.candidateCount = 0;
            r.candidatesJson = '[]';
            return new List<Response>{ r };
        }
        r.found = true;
        r.accountId = a.Id;
        r.accountName = a.Name;

        // 1. 고객이 발주한 Product Id + Family 수집
        Set<Id> purchasedProductIds = new Set<Id>();
        Set<String> purchasedFamilies = new Set<String>();
        for (OrderItem oi : [
            SELECT Product2Id, Product2.Family
            FROM OrderItem
            WHERE Order.AccountId = :a.Id
              AND Product2Id != null
        ]) {
            purchasedProductIds.add(oi.Product2Id);
            if (String.isNotBlank(oi.Product2.Family)) {
                purchasedFamilies.add(oi.Product2.Family);
            }
        }

        if (purchasedProductIds.isEmpty()) {
            r.summary = a.Name + ' 의 과거 발주 이력이 없어 cross-sell 후보 산출 불가. 첫 거래는 일반 카탈로그에서.';
            r.candidateCount = 0;
            r.candidatesJson = '[]';
            return new List<Response>{ r };
        }

        // 2. 같은 Family 내 미구매 Product 인기순 (전체 OrderItem 수)
        Map<Id, Integer> popularity = new Map<Id, Integer>();
        Map<Id, Product2> productMap = new Map<Id, Product2>();

        // (a) 같은 Family 내 활성 Product 후보
        List<Product2> familyProducts = purchasedFamilies.isEmpty()
            ? new List<Product2>()
            : [SELECT Id, Name, ProductCode, Family
               FROM Product2
               WHERE Family IN :purchasedFamilies AND IsActive = true
               LIMIT 200];
        for (Product2 p : familyProducts) {
            if (purchasedProductIds.contains(p.Id)) continue;
            productMap.put(p.Id, p);
            popularity.put(p.Id, 0);
        }

        if (productMap.isEmpty()) {
            r.summary = a.Name + ' 가 발주한 Family 의 다른 Product 가 카탈로그에 없습니다.';
            r.candidateCount = 0;
            r.candidatesJson = '[]';
            return new List<Response>{ r };
        }

        // (b) 인기도 — 후보 Product 의 OrderItem 합계
        for (AggregateResult ar : [
            SELECT Product2Id pid, COUNT(Id) cnt
            FROM OrderItem
            WHERE Product2Id IN :productMap.keySet()
            GROUP BY Product2Id
        ]) {
            Id pid = (Id) ar.get('pid');
            popularity.put(pid, (Integer) ar.get('cnt'));
        }

        // 3. 인기순 정렬 후 상위 N
        List<Candidate> candidates = new List<Candidate>();
        for (Id pid : popularity.keySet()) {
            Product2 p = productMap.get(pid);
            Candidate c = new Candidate();
            c.productId = pid;
            c.productName = p.Name;
            c.productCode = p.ProductCode;
            c.family = p.Family;
            c.popularity = popularity.get(pid);
            candidates.add(c);
        }
        candidates.sort(new CandidateComparator());

        if (candidates.size() > cap) {
            List<Candidate> trimmed = new List<Candidate>();
            for (Integer i = 0; i < cap; i++) trimmed.add(candidates[i]);
            candidates = trimmed;
        }

        r.candidateCount = candidates.size();
        r.candidatesJson = JSON.serialize(candidates);
        r.summary = buildSummary(a.Name, purchasedFamilies, candidates);
        return new List<Response>{ r };
    }

    private static Account findAccount(Request req) {
        if (req.accountId != null) {
            List<Account> byId = [SELECT Id, Name FROM Account WHERE Id = :req.accountId LIMIT 1];
            return byId.isEmpty() ? null : byId[0];
        }
        if (String.isNotBlank(req.accountName)) {
            String pattern = '%' + req.accountName.trim() + '%';
            List<Account> byName = [
                SELECT Id, Name FROM Account WHERE Name LIKE :pattern
                ORDER BY Total_AR__c DESC NULLS LAST LIMIT 1
            ];
            return byName.isEmpty() ? null : byName[0];
        }
        return null;
    }

    @TestVisible
    private static String buildSummary(String accName, Set<String> families, List<Candidate> cands) {
        if (cands.isEmpty()) return accName + ' 추천 후보 없음.';
        List<String> names = new List<String>();
        for (Integer i = 0; i < Math.min(cands.size(), 3); i++) names.add(cands[i].productName);
        String head = accName + ' 의 발주 카테고리(' + (families.isEmpty() ? '미상' : String.join(new List<String>(families), '/')) + ')';
        return head + ' 기반 추천 ' + cands.size() + '건 — ' + String.join(names, ', ') +
               (cands.size() > 3 ? ' 외 ' + (cands.size() - 3) + '건' : '') + '.';
    }

    public class Candidate {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public Integer popularity;
    }

    /** 인기도 내림차순. */
    public class CandidateComparator implements System.Comparator<Candidate> {
        public Integer compare(Candidate a, Candidate b) {
            Integer pa = a.popularity == null ? 0 : a.popularity;
            Integer pb = b.popularity == null ? 0 : b.popularity;
            if (pa == pb) return 0;
            return pa < pb ? 1 : -1;
        }
    }
}
