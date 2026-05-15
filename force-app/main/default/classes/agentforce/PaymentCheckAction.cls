/**
 * PaymentCheckAction — Agentforce Action: 입금/회수/미수 현황 통합 조회 (Day 15).
 *
 * mode 분기:
 *   today    : 오늘(Date.today()) Paid Payment 건수·총액 + 상위 입금 고객사
 *   week     : 최근 7일 Paid Payment 합계 + 상위 입금 고객사
 *   account  : 특정 고객사 — 청구 / 누적입금 / 잔액 + 최근 입금 5건
 *   atrisk   : 미수금 보유 고객사 Top N (Account.Total_AR__c 기준)
 *
 * ReAct 라우터(AgentRouter Prompt) 가 mode 를 자동 선택.
 * 키워드 라우터 없음 — ReAct 만 사용.
 *
 * @group Agentforce
 */
public with sharing class PaymentCheckAction {

    private static final Integer DEFAULT_TOP_N = 5;
    private static final String PAID = 'Paid';

    public class Request {
        @InvocableVariable(
            label='모드'
            description='today / week / account / atrisk. 기본값 today.'
            required=false
        )
        public String mode;

        @InvocableVariable(
            label='고객사 Id'
            description='account 모드 시 사용. 미지정 + accountName 도 없으면 컨텍스트로 보강.'
            required=false
        )
        public Id accountId;

        @InvocableVariable(
            label='고객사명'
            description='account 모드 시 회사명 매칭. exact 우선, fallback LIKE.'
            required=false
        )
        public String accountName;

        @InvocableVariable(
            label='상위 N건'
            description='today/week/atrisk 모드에서 노출 행 수. 기본 5.'
            required=false
        )
        public Integer topN;
    }

    public class Response {
        @InvocableVariable(label='한국어 요약') public String summary;
        @InvocableVariable(label='적용된 모드') public String mode;
        @InvocableVariable(label='데이터 있음') public Boolean found;
        @InvocableVariable(label='건수') public Integer count;
        @InvocableVariable(label='합계 금액 (₩)') public Decimal totalAmount;
        @InvocableVariable(label='고객사 Id') public Id accountId;
        @InvocableVariable(label='고객사명') public String accountName;
        @InvocableVariable(label='상세 JSON') public String detailsJson;
    }

    @InvocableMethod(
        label='Check Payments'
        description='입금/회수/미수 현황 조회. mode=today(오늘 입금) / week(최근 7일 회수) / account(특정 고객사 잔액) / atrisk(미수금 상위 Top N).'
        category='Sales Cockpit'
    )
    public static List<Response> run(List<Request> reqs) {
        Request req = (reqs == null || reqs.isEmpty()) ? new Request() : reqs[0];
        String mode = String.isBlank(req.mode) ? 'today' : req.mode.toLowerCase().trim();
        Integer topN = (req.topN == null || req.topN <= 0) ? DEFAULT_TOP_N : req.topN;

        Response r = new Response();
        r.mode = mode;
        r.totalAmount = 0;
        r.count = 0;
        r.found = false;

        if ('today'.equals(mode)) {
            return new List<Response>{ runRange(r, Date.today(), Date.today(), '오늘', topN) };
        }
        if ('week'.equals(mode)) {
            return new List<Response>{ runRange(r, Date.today().addDays(-6), Date.today(), '최근 7일', topN) };
        }
        if ('account'.equals(mode)) {
            return new List<Response>{ runAccount(r, req.accountId, req.accountName) };
        }
        if ('atrisk'.equals(mode)) {
            return new List<Response>{ runAtRisk(r, topN) };
        }
        // 알 수 없는 모드 → today 로 보정
        r.mode = 'today';
        return new List<Response>{ runRange(r, Date.today(), Date.today(), '오늘', topN) };
    }

    // ─────────────────────────────────────────────────────────────────────
    // today / week 공통
    // ─────────────────────────────────────────────────────────────────────

    private static Response runRange(Response r, Date fromD, Date toD, String label, Integer topN) {
        List<Payment__c> payments = [
            SELECT Id, Paid_Date__c, Paid_Amount__c, Memo__c,
                   Order__c, Order__r.Name,
                   Order__r.AccountId, Order__r.Account.Name
            FROM Payment__c
            WHERE Status__c = :PAID
              AND Paid_Date__c >= :fromD AND Paid_Date__c <= :toD
            ORDER BY Paid_Date__c DESC, CreatedDate DESC
            LIMIT 200
        ];

        Decimal sum = 0;
        Map<Id, Decimal> byAcct = new Map<Id, Decimal>();
        Map<Id, String> nameByAcct = new Map<Id, String>();
        for (Payment__c p : payments) {
            Decimal amt = nz(p.Paid_Amount__c);
            sum += amt;
            Id aid = (p.Order__r == null) ? null : p.Order__r.AccountId;
            if (aid != null) {
                byAcct.put(aid, nz(byAcct.get(aid)) + amt);
                if (p.Order__r.Account != null) nameByAcct.put(aid, p.Order__r.Account.Name);
            }
        }

        List<Map<String, Object>> topAccts = topAccountsByAmount(byAcct, nameByAcct, topN);

        r.count = payments.size();
        r.totalAmount = sum;
        r.found = !payments.isEmpty();
        r.detailsJson = JSON.serialize(new Map<String, Object>{
            'rangeFrom'   => fromD,
            'rangeTo'     => toD,
            'totalAmount' => sum,
            'payments'    => payments,
            'topAccounts' => topAccts
        });

        if (payments.isEmpty()) {
            r.summary = label + ' 입금 내역이 없어요.';
        } else if (!topAccts.isEmpty()) {
            r.summary = label + ' 입금 ' + payments.size() + '건 — ₩' + formatKrw(sum)
                + '. 최다 — ' + topAccts[0].get('accountName')
                + ' ₩' + formatKrw((Decimal) topAccts[0].get('amount')) + '.';
        } else {
            r.summary = label + ' 입금 ' + payments.size() + '건 — ₩' + formatKrw(sum) + '.';
        }
        return r;
    }

    // ─────────────────────────────────────────────────────────────────────
    // account 모드
    // ─────────────────────────────────────────────────────────────────────

    private static Response runAccount(Response r, Id accountId, String accountName) {
        Account acct = resolveAccount(accountId, accountName);
        if (acct == null) {
            r.summary = '고객사를 찾지 못했어요. 회사명을 다시 확인해 주세요.';
            r.detailsJson = '{}';
            return r;
        }
        r.accountId = acct.Id;
        r.accountName = acct.Name;

        List<Order> orders = [
            SELECT Id, Name, OrderNumber, TotalAmount, Total_Paid_Amount__c, Outstanding_Amount__c,
                   Status, EffectiveDate, EndDate
            FROM Order
            WHERE AccountId = :acct.Id
            ORDER BY EffectiveDate DESC NULLS LAST
            LIMIT 50
        ];

        Decimal totalBilled = 0, totalPaid = 0, outstanding = 0;
        for (Order o : orders) {
            totalBilled += nz(o.TotalAmount);
            totalPaid   += nz(o.Total_Paid_Amount__c);
            outstanding += nz(o.Outstanding_Amount__c);
        }
        if (outstanding < 0) outstanding = 0;

        List<Payment__c> recent = [
            SELECT Id, Paid_Date__c, Paid_Amount__c, Memo__c,
                   Order__c, Order__r.Name
            FROM Payment__c
            WHERE Status__c = :PAID AND Order__r.AccountId = :acct.Id
            ORDER BY Paid_Date__c DESC, CreatedDate DESC
            LIMIT 5
        ];

        r.count = orders.size();
        r.totalAmount = outstanding;
        r.found = true;
        r.detailsJson = JSON.serialize(new Map<String, Object>{
            'accountId'      => acct.Id,
            'accountName'    => acct.Name,
            'orderCount'     => orders.size(),
            'totalBilled'    => totalBilled,
            'totalPaid'      => totalPaid,
            'outstanding'    => outstanding,
            'orders'         => orders,
            'recentPayments' => recent
        });

        if (orders.isEmpty()) {
            r.summary = acct.Name + ' 은 등록된 Order 가 없어요.';
        } else if (outstanding <= 0 && totalBilled > 0) {
            r.summary = acct.Name + ' — 청구 ₩' + formatKrw(totalBilled)
                + ' / 누적 입금 ₩' + formatKrw(totalPaid) + ' / 잔액 0원, 완납 상태예요.';
        } else {
            r.summary = acct.Name + ' — 청구 ₩' + formatKrw(totalBilled)
                + ' / 누적 입금 ₩' + formatKrw(totalPaid)
                + ' / 잔액 ₩' + formatKrw(outstanding) + '.';
        }
        return r;
    }

    // ─────────────────────────────────────────────────────────────────────
    // atrisk 모드
    // ─────────────────────────────────────────────────────────────────────

    private static Response runAtRisk(Response r, Integer topN) {
        List<Account> arAccounts = [
            SELECT Id, Name, Total_AR__c, Long_Term_Debtor__c
            FROM Account
            WHERE Total_AR__c > 0
            ORDER BY Total_AR__c DESC NULLS LAST
            LIMIT :topN
        ];

        Decimal sum = 0;
        Integer longTermCount = 0;
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Account a : arAccounts) {
            Decimal ar = nz(a.Total_AR__c);
            sum += ar;
            Boolean lt = a.Long_Term_Debtor__c == true;
            if (lt) longTermCount++;
            rows.add(new Map<String, Object>{
                'accountId'       => a.Id,
                'accountName'     => a.Name,
                'totalAR'         => ar,
                'longTermDebtor'  => lt
            });
        }

        r.count = arAccounts.size();
        r.totalAmount = sum;
        r.found = !arAccounts.isEmpty();
        r.detailsJson = JSON.serialize(new Map<String, Object>{
            'topAccounts'   => rows,
            'longTermCount' => longTermCount
        });

        if (arAccounts.isEmpty()) {
            r.summary = '미수금 보유 고객사가 없어요. 자금 회수 양호.';
        } else {
            String suffix = longTermCount > 0
                ? ' 장기미수 ' + longTermCount + '곳 포함.'
                : '';
            r.summary = '미수금 상위 ' + arAccounts.size() + '곳 합계 ₩' + formatKrw(sum)
                + '. 최다 — ' + arAccounts[0].Name
                + ' ₩' + formatKrw(arAccounts[0].Total_AR__c) + '.' + suffix;
        }
        return r;
    }

    // ─────────────────────────────────────────────────────────────────────
    // helpers
    // ─────────────────────────────────────────────────────────────────────

    private static Account resolveAccount(Id accountId, String accountName) {
        if (accountId != null) {
            try {
                return [SELECT Id, Name, Total_AR__c, Long_Term_Debtor__c
                        FROM Account WHERE Id = :accountId LIMIT 1];
            } catch (QueryException e) {
                return null;
            }
        }
        if (String.isBlank(accountName)) return null;
        String name = accountName.trim();
        // exact match 우선
        List<Account> exact = [
            SELECT Id, Name, Total_AR__c, Long_Term_Debtor__c
            FROM Account WHERE Name = :name LIMIT 1
        ];
        if (!exact.isEmpty()) return exact[0];
        // LIKE fallback ('like' 는 Apex 예약어라 변수명으로 못 씀)
        String pat = '%' + name + '%';
        List<Account> fuzzy = [
            SELECT Id, Name, Total_AR__c, Long_Term_Debtor__c
            FROM Account WHERE Name LIKE :pat
            ORDER BY Name LIMIT 1
        ];
        return fuzzy.isEmpty() ? null : fuzzy[0];
    }

    @TestVisible
    private static List<Map<String, Object>> topAccountsByAmount(
        Map<Id, Decimal> byAcct, Map<Id, String> nameByAcct, Integer topN
    ) {
        List<Id> sorted = new List<Id>(byAcct.keySet());
        // Apex List.sort() 는 SObject 만 지원 → 수동 정렬 (n 작아서 O(n^2) 충분)
        for (Integer i = 0; i < sorted.size(); i++) {
            for (Integer j = i + 1; j < sorted.size(); j++) {
                if (nz(byAcct.get(sorted[j])) > nz(byAcct.get(sorted[i]))) {
                    Id tmp = sorted[i]; sorted[i] = sorted[j]; sorted[j] = tmp;
                }
            }
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        Integer cap = Math.min(topN, sorted.size());
        for (Integer i = 0; i < cap; i++) {
            out.add(new Map<String, Object>{
                'accountId'   => sorted[i],
                'accountName' => nameByAcct.get(sorted[i]),
                'amount'      => byAcct.get(sorted[i])
            });
        }
        return out;
    }

    private static Decimal nz(Decimal v) { return v == null ? 0 : v; }

    @TestVisible
    private static String formatKrw(Decimal v) {
        if (v == null) return '0';
        // Decimal.format() 은 locale-aware (ko_KR 에서 1,234,567 반환)
        return v.setScale(0, System.RoundingMode.HALF_UP).format();
    }
}
