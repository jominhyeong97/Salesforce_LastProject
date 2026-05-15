/**
 * GetOrderAtRiskAction — Agentforce Action: 납기 위험 Order 목록.
 *
 * Order.Delivery_Risk_Score__c >= 임계값(기본 70) 목록을 반환.
 * 동기화는 시연용 [🔄 ERP 동기화] 버튼이 담당하므로 이 Action 은 저장된 값만 읽음.
 *
 * 사용 시점 — "위험 Order", "납기 위험", "사전 통보 필요" 같은 자연어 질의.
 *
 * @group Agentforce
 */
public with sharing class GetOrderAtRiskAction {

    private static final Integer DEFAULT_THRESHOLD = 70;
    private static final Integer DEFAULT_LIMIT     = 10;

    public class Request {
        @InvocableVariable(
            label='최소 위험 점수'
            description='이 점수 이상의 Order 만 반환. 기본 70.'
            required=false
        )
        public Integer minRiskScore;

        @InvocableVariable(
            label='최대 반환 건수'
            description='반환할 Order 최대 개수. 기본 10, 최대 50.'
            required=false
        )
        public Integer maxResults;
    }

    public class Response {
        @InvocableVariable(label='한국어 요약')
        public String summary;

        @InvocableVariable(label='위험 Order 건수')
        public Integer riskCount;

        @InvocableVariable(label='상세 항목 JSON')
        public String detailsJson;
    }

    @InvocableMethod(
        label='Get Orders At Risk'
        description='납기 위험 점수 임계값 이상의 Order 목록을 반환합니다. Delivery_Risk_Score__c, PoNumber, Production_Status__c, 고객사명, 마지막 ERP 동기화 시각 포함.'
        category='Sales Cockpit'
    )
    public static List<Response> run(List<Request> reqs) {
        Request req = (reqs != null && !reqs.isEmpty()) ? reqs[0] : new Request();
        Integer threshold = (req.minRiskScore == null || req.minRiskScore < 0) ? DEFAULT_THRESHOLD : req.minRiskScore;
        Integer maxN      = (req.maxResults   == null || req.maxResults   <= 0) ? DEFAULT_LIMIT     : Math.min(req.maxResults, 50);

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Integer high = 0;
        Integer mid  = 0;
        for (Order o : [
            SELECT Id, Name, PoNumber, Production_Status__c, Delivery_Risk_Score__c,
                   Last_ErpSync_At__c, Account.Name
            FROM Order
            WHERE Delivery_Risk_Score__c != null
              AND Delivery_Risk_Score__c >= :threshold
            ORDER BY Delivery_Risk_Score__c DESC
            LIMIT :maxN
        ]) {
            rows.add(new Map<String, Object>{
                'orderId'          => o.Id,
                'orderName'        => o.Name,
                'poNumber'         => o.PoNumber,
                'accountName'      => (o.Account != null ? o.Account.Name : null),
                'productionStatus' => o.Production_Status__c,
                'riskScore'        => Integer.valueOf(o.Delivery_Risk_Score__c),
                'lastErpSyncAt'    => o.Last_ErpSync_At__c
            });
            if (o.Delivery_Risk_Score__c >= 85) high++;
            else mid++;
        }

        Response r = new Response();
        r.riskCount   = rows.size();
        r.summary     = buildSummary(threshold, rows.size(), high, mid);
        r.detailsJson = JSON.serialize(rows);
        return new List<Response>{ r };
    }

    @TestVisible
    private static String buildSummary(Integer threshold, Integer total, Integer high, Integer mid) {
        if (total == 0) {
            return '위험 점수 ' + threshold + ' 이상 Order 없음. 납기 정상.';
        }
        String tail = (high > 0)
            ? ' 그 중 대형지연(85+) ' + high + '건 — 즉시 사전 통보 메일 검토.'
            : '';
        return '위험 Order ' + total + '건 (' + threshold + '점 이상).' + tail;
    }
}
