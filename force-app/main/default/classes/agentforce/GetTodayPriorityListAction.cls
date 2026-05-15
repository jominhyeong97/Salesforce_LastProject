/**
 * GetTodayPriorityListAction — Agentforce Action: AE 오늘 우선순위 통합 목록.
 *
 * AeCockpitService.load() 5카드(newRfqs/priorityLeads/sentQuotes/riskyOrders/arActions)를
 * Agent 가 자연어로 요약 가능한 형태로 반환.
 *
 * 사용 시점 — AE 가 "오늘 할 일", "내 우선순위", "급한 것부터" 같은 자연어 질의.
 *
 * @group Agentforce
 */
public with sharing class GetTodayPriorityListAction {

    public class Request {
        @InvocableVariable(
            label='카테고리 필터'
            description='특정 카테고리만 반환. 빈값=전체. 허용값: lead/quote/order/ar'
            required=false
        )
        public String category;
    }

    public class Response {
        @InvocableVariable(label='한국어 요약')
        public String summary;

        @InvocableVariable(label='신규 RFQ 건수')
        public Integer newRfqCount;

        @InvocableVariable(label='우선 Lead 건수')
        public Integer priorityLeadCount;

        @InvocableVariable(label='발송 Quote 건수')
        public Integer sentQuoteCount;

        @InvocableVariable(label='위험 Order 건수')
        public Integer riskyOrderCount;

        @InvocableVariable(label='미수금 액션 건수')
        public Integer arActionCount;

        @InvocableVariable(label='상세 항목 JSON')
        public String detailsJson;
    }

    @InvocableMethod(
        label='Get Today Priority List'
        description='AE 의 오늘 우선순위 통합 목록을 5 카테고리(신규 RFQ / 우선 Lead / 발송 Quote / 위험 Order / 미수금)로 반환합니다. 자연어 질의 "오늘 할 일", "급한 것부터" 등에 사용.'
        category='Sales Cockpit'
    )
    public static List<Response> run(List<Request> reqs) {
        AeCockpitService.Dashboard d = AeCockpitService.load();

        Response r = new Response();
        r.newRfqCount       = d.newRfqs       == null ? 0 : d.newRfqs.size();
        r.priorityLeadCount = d.priorityLeads == null ? 0 : d.priorityLeads.size();
        r.sentQuoteCount    = d.sentQuotes    == null ? 0 : d.sentQuotes.size();
        r.riskyOrderCount   = d.riskyOrders   == null ? 0 : d.riskyOrders.size();
        r.arActionCount     = d.arActions     == null ? 0 : d.arActions.size();

        r.summary = buildSummary(d);
        r.detailsJson = JSON.serialize(buildDetails(d));

        return new List<Response>{ r };
    }

    @TestVisible
    private static String buildSummary(AeCockpitService.Dashboard d) {
        Integer total = (d.newRfqs == null ? 0 : d.newRfqs.size())
                      + (d.priorityLeads == null ? 0 : d.priorityLeads.size())
                      + (d.sentQuotes == null ? 0 : d.sentQuotes.size())
                      + (d.riskyOrders == null ? 0 : d.riskyOrders.size())
                      + (d.arActions == null ? 0 : d.arActions.size());

        List<String> parts = new List<String>();
        if (d.newRfqs != null && !d.newRfqs.isEmpty()) {
            parts.add('신규 RFQ ' + d.newRfqs.size() + '건');
        }
        if (d.priorityLeads != null && !d.priorityLeads.isEmpty()) {
            parts.add('우선 Lead ' + d.priorityLeads.size() + '건');
        }
        if (d.sentQuotes != null && !d.sentQuotes.isEmpty()) {
            parts.add('발송 Quote ' + d.sentQuotes.size() + '건');
        }
        if (d.riskyOrders != null && !d.riskyOrders.isEmpty()) {
            parts.add('위험 Order ' + d.riskyOrders.size() + '건');
        }
        if (d.arActions != null && !d.arActions.isEmpty()) {
            parts.add('미수금 액션 ' + d.arActions.size() + '건');
        }

        if (total == 0) return '오늘 우선순위 없음. 모든 영업 항목 정상.';
        return '오늘 우선순위 ' + total + '건 — ' + String.join(parts, ', ') + '.';
    }

    private static Map<String, Object> buildDetails(AeCockpitService.Dashboard d) {
        return new Map<String, Object>{
            'newRfqs'       => d.newRfqs,
            'priorityLeads' => d.priorityLeads,
            'sentQuotes'    => d.sentQuotes,
            'riskyOrders'   => d.riskyOrders,
            'arActions'     => d.arActions
        };
    }
}
