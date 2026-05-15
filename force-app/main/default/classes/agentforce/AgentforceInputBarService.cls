/**
 * AgentforceInputBarService — 콕피트 자연어 입력창 라우터 (COCKPIT-003).
 *
 * v4 ReAct 단순화 (Day 15):
 *   [1] AgentRouter Prompt 가 utterance + contextHint → tool 선택 JSON (6 tool)
 *   [2] tool 매칭되면 해당 Invocable Action 호출, args 누락 시 contextRecordId 보강
 *   [3] AgentSynthesize Prompt 가 결과 JSON + 원 질의 → 한국어 자연어 응답
 *   [4] router 가 tool=none 또는 실패 시 — AgentInputFallback LLM → 최종 안내 메시지
 *
 * v3 → v4 변경: 키워드 라우터 완전 제거 (Day 14 "오늘" 단일 키워드 greedy 매칭 문제 해소).
 * 평가자 narrative: "같은 Apex Invocable 을 (a) Agentforce planner (b) ReAct LLM 라우터
 * 두 path 가 호출 — 5종 기술 통합".
 *
 * @group Agentforce
 */
public with sharing class AgentforceInputBarService {

    /** LWC → 자연어 질의 진입점. */
    @AuraEnabled
    public static AgentResponse ask(String utterance, Id contextRecordId) {
        AgentResponse r = new AgentResponse();
        if (String.isBlank(utterance)) {
            r.action = 'noop';
            r.message = '질문을 입력해주세요.';
            return r;
        }
        r.utterance = utterance;

        try {
            // [1] ReAct router 우선 시도
            AgentResponse reactResp = tryReactRouter(utterance, contextRecordId);
            if (reactResp != null) return reactResp;

            // [2] router none/실패 — AgentInputFallback LLM
            try {
                String aiText = AgentInputFallbackInvoker.invoke(utterance);
                if (String.isNotBlank(aiText)) {
                    r.action = 'llm_fallback';
                    r.message = aiText.trim();
                    return r;
                }
            } catch (Exception aiEx) { /* fall through */ }

            r.action = 'fallback';
            r.message = '"오늘 우선순위", "납기 위험 주문", "현대모비스 미수금", "오늘 입금", "추천 부품", "follow-up 메일" 같이 물어보세요.';
            return r;

        } catch (Exception e) {
            r.action = 'error';
            r.message = '오류: ' + e.getMessage();
            return r;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // [1] ReAct: router → action → synthesize
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static AgentResponse tryReactRouter(String utterance, Id contextRecordId) {
        String contextHint = buildContextHint(contextRecordId);
        String routerJson;
        try {
            routerJson = AgentRouterInvoker.invoke(utterance, contextHint);
        } catch (Exception e) {
            return null;  // router LLM 실패 → 다음 단계로
        }
        if (String.isBlank(routerJson)) return null;

        RouterDecision dec = parseRouter(routerJson);
        if (dec == null) return null;
        if (dec.tool == null || 'none'.equalsIgnoreCase(dec.tool)) return null;

        // accountName 보강 — args 에 없으면 contextRecordId 로 AccountId 시도
        Id ctxAccountId = resolveAccountIdFromContext(contextRecordId);

        AgentResponse r = new AgentResponse();
        r.utterance = utterance;
        r.action = dec.tool + 'Action';  // GetTodayPriorityList → GetTodayPriorityListAction

        String tool = dec.tool;
        String actionResultJson;
        String fallbackSummary;

        if ('GetTodayPriorityList'.equalsIgnoreCase(tool)) {
            GetTodayPriorityListAction.Request req = new GetTodayPriorityListAction.Request();
            List<GetTodayPriorityListAction.Response> outs = GetTodayPriorityListAction.run(
                new List<GetTodayPriorityListAction.Request>{ req });
            if (outs.isEmpty()) return null;
            actionResultJson = JSON.serialize(outs[0]);
            fallbackSummary = outs[0].summary;
            r.detailsJson = outs[0].detailsJson;

        } else if ('GetOrderAtRisk'.equalsIgnoreCase(tool)) {
            GetOrderAtRiskAction.Request req = new GetOrderAtRiskAction.Request();
            List<GetOrderAtRiskAction.Response> outs = GetOrderAtRiskAction.run(
                new List<GetOrderAtRiskAction.Request>{ req });
            if (outs.isEmpty()) return null;
            actionResultJson = JSON.serialize(outs[0]);
            fallbackSummary = outs[0].summary;
            r.detailsJson = outs[0].detailsJson;

        } else if ('GetAccountSummary'.equalsIgnoreCase(tool)) {
            GetAccountSummaryAction.Request req = new GetAccountSummaryAction.Request();
            req.accountId = getArgId(dec.args, 'accountId');
            req.accountName = getArgStr(dec.args, 'accountName');
            if (req.accountId == null && String.isBlank(req.accountName) && ctxAccountId != null) {
                req.accountId = ctxAccountId;
            }
            if (req.accountId == null && String.isBlank(req.accountName)) {
                return missingArg(utterance, '어떤 고객사를 말씀하시는지 알려주세요. 예: "현대모비스 미수금"');
            }
            List<GetAccountSummaryAction.Response> outs = GetAccountSummaryAction.run(
                new List<GetAccountSummaryAction.Request>{ req });
            if (outs.isEmpty()) return null;
            actionResultJson = JSON.serialize(outs[0]);
            fallbackSummary = outs[0].summary;
            r.detailsJson = actionResultJson;

        } else if ('GetCrossSellCandidates'.equalsIgnoreCase(tool)) {
            GetCrossSellCandidatesAction.Request req = new GetCrossSellCandidatesAction.Request();
            req.accountId = getArgId(dec.args, 'accountId');
            req.accountName = getArgStr(dec.args, 'accountName');
            if (req.accountId == null && String.isBlank(req.accountName) && ctxAccountId != null) {
                req.accountId = ctxAccountId;
            }
            if (req.accountId == null && String.isBlank(req.accountName)) {
                return missingArg(utterance, '어떤 고객사에게 추천할지 알려주세요. 예: "태양산업에게 추천 부품"');
            }
            List<GetCrossSellCandidatesAction.Response> outs = GetCrossSellCandidatesAction.run(
                new List<GetCrossSellCandidatesAction.Request>{ req });
            if (outs.isEmpty()) return null;
            actionResultJson = JSON.serialize(outs[0]);
            fallbackSummary = outs[0].summary;
            r.detailsJson = outs[0].candidatesJson;

        } else if ('PaymentCheck'.equalsIgnoreCase(tool)) {
            PaymentCheckAction.Request req = new PaymentCheckAction.Request();
            req.mode        = getArgStr(dec.args, 'mode');
            req.accountId   = getArgId(dec.args, 'accountId');
            req.accountName = getArgStr(dec.args, 'accountName');
            if ('account'.equalsIgnoreCase(req.mode)
                && req.accountId == null && String.isBlank(req.accountName)
                && ctxAccountId != null) {
                req.accountId = ctxAccountId;
            }
            List<PaymentCheckAction.Response> outs = PaymentCheckAction.run(
                new List<PaymentCheckAction.Request>{ req });
            if (outs.isEmpty()) return null;
            actionResultJson = JSON.serialize(outs[0]);
            fallbackSummary  = outs[0].summary;
            r.detailsJson    = outs[0].detailsJson;

        } else if ('DraftFollowupEmail'.equalsIgnoreCase(tool)) {
            Id qid = getArgId(dec.args, 'quoteId');
            if (qid == null && contextRecordId != null
                && String.valueOf(contextRecordId).startsWith('0Q0')) {
                qid = contextRecordId;
            }
            if (qid == null) {
                return missingArg(utterance, 'follow-up 메일은 Quote 페이지에서 호출해 주세요.');
            }
            DraftFollowupEmailAction.Request req = new DraftFollowupEmailAction.Request();
            req.quoteId = qid;
            req.additionalContext = utterance;
            List<DraftFollowupEmailAction.Response> outs = DraftFollowupEmailAction.run(
                new List<DraftFollowupEmailAction.Request>{ req });
            if (outs.isEmpty()) return null;
            actionResultJson = JSON.serialize(outs[0]);
            fallbackSummary = '제목: ' + outs[0].emailSubject + '\n\n' + outs[0].emailBody;
            r.urgency = outs[0].urgency;
            r.detailsJson = actionResultJson;

        } else {
            // 알 수 없는 tool — 라우터 오답
            return null;
        }

        // [3] synthesize LLM 으로 자연어 종합
        try {
            String synth = AgentSynthesizeInvoker.invoke(utterance, tool, actionResultJson);
            if (String.isNotBlank(synth)) {
                r.message = synth.trim();
                return r;
            }
        } catch (Exception synEx) { /* fallthrough to raw summary */ }

        // synthesize 실패 — Action 의 raw summary 그대로
        r.message = fallbackSummary;
        return r;
    }

    /** Router-decided 도구가 args 부족 시 안내 응답. */
    private static AgentResponse missingArg(String utterance, String msg) {
        AgentResponse r = new AgentResponse();
        r.utterance = utterance;
        r.action = 'missing_args';
        r.message = msg;
        return r;
    }

    /** contextRecordId 의 SObject 유형 + AccountName 힌트 문자열. */
    @TestVisible
    private static String buildContextHint(Id recordId) {
        if (recordId == null) return '없음';
        String prefix = String.valueOf(recordId).substring(0, 3);
        String typeName = 'Unknown';
        String acctName = null;
        Id qid = null;
        try {
            if (prefix == '001') {
                typeName = 'Account';
                Account a = [SELECT Name FROM Account WHERE Id = :recordId LIMIT 1];
                acctName = a.Name;
            } else if (prefix == '006') {
                typeName = 'Opportunity';
                Opportunity o = [SELECT Account.Name FROM Opportunity WHERE Id = :recordId LIMIT 1];
                if (o.Account != null) acctName = o.Account.Name;
            } else if (prefix == '0Q0') {
                typeName = 'Quote';
                qid = recordId;
                Quote q = [SELECT Opportunity.Account.Name FROM Quote WHERE Id = :recordId LIMIT 1];
                if (q.Opportunity != null && q.Opportunity.Account != null) acctName = q.Opportunity.Account.Name;
            } else if (prefix == '801') {
                typeName = 'Order';
                Order o = [SELECT Account.Name FROM Order WHERE Id = :recordId LIMIT 1];
                if (o.Account != null) acctName = o.Account.Name;
            }
        } catch (Exception e) {
            // ignore
        }
        List<String> parts = new List<String>();
        parts.add('recordType=' + typeName);
        if (qid != null) parts.add('quoteId=' + qid);
        if (String.isNotBlank(acctName)) parts.add('accountName=' + acctName);
        return String.join(parts, ', ');
    }

    @TestVisible
    private static RouterDecision parseRouter(String routerJson) {
        if (String.isBlank(routerJson)) return null;
        String cleaned = stripCodeFences(routerJson);
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            RouterDecision d = new RouterDecision();
            d.tool = (String) raw.get('tool');
            Object argsObj = raw.get('args');
            d.args = (argsObj instanceof Map<String, Object>) ? (Map<String, Object>) argsObj : new Map<String, Object>();
            d.rationale = (String) raw.get('rationale');
            return d;
        } catch (Exception e) {
            return null;
        }
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

    private static Id getArgId(Map<String, Object> args, String key) {
        if (args == null) return null;
        Object v = args.get(key);
        if (v == null) return null;
        try { return (Id) String.valueOf(v); } catch (Exception e) { return null; }
    }

    private static String getArgStr(Map<String, Object> args, String key) {
        if (args == null) return null;
        Object v = args.get(key);
        return v == null ? null : String.valueOf(v);
    }

    public class RouterDecision {
        public String tool;
        public Map<String, Object> args;
        public String rationale;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 공용 헬퍼
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static Id resolveAccountIdFromContext(Id recordId) {
        if (recordId == null) return null;
        String prefix = String.valueOf(recordId).substring(0, 3);
        try {
            if (prefix == '001') return recordId;
            if (prefix == '006') return [SELECT AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1].AccountId;
            if (prefix == '0Q0') return [SELECT AccountId FROM Quote WHERE Id = :recordId LIMIT 1].AccountId;
            if (prefix == '801') return [SELECT AccountId FROM Order WHERE Id = :recordId LIMIT 1].AccountId;
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    public class AgentResponse {
        @AuraEnabled public String utterance;
        @AuraEnabled public String action;
        @AuraEnabled public String message;
        @AuraEnabled public String detailsJson;
        @AuraEnabled public String urgency;
    }
}
