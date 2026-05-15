/**
 * OppScoreService — Opportunity 거래 점수 + 위험 요소 계산 (정량, Apex).
 *
 * 점수 산식 (max 100):
 *   - stageScore       : 단계 진행 0~50 (발굴 10/견적 작성 20/견적 발송 30/협상 40/수주 50)
 *   - activityScore    : 최근 14일 활동 0~20 (Task/Event 합산)
 *   - accountScore     : Account 신용 0~15 (External_Credit_Score__c, Long_Term_Debtor__c 감점)
 *   - engagementScore  : Quote/이메일 응답 0~15 (존재/발송/오픈)
 *
 * 위험 요소 (riskFactors):
 *   - 활동 0건 / 견적 미작성 / 단계 게이트 미충족(사업자번호) / 장기미수 / 실주
 *
 * @group Quote
 */
public with sharing class OppScoreService {

    public class Score {
        public Integer total;
        public Integer stageScore;
        public Integer activityScore;
        public Integer accountScore;
        public Integer engagementScore;
        public List<String> riskFactors;
    }

    private static final Map<String, Integer> STAGE_SCORE = new Map<String, Integer>{
        '발굴'      => 10,
        '견적 작성' => 20,
        '견적 발송' => 30,
        '협상'      => 40,
        '수주'      => 50,
        '실주'      => 0
    };

    public static Score calculate(Id opportunityId) {
        Score s = new Score();
        s.riskFactors = new List<String>();

        Opportunity opp = [
            SELECT Id, StageName, Amount, CloseDate,
                   Account.Name, Account.Business_Number__c, Account.External_Credit_Score__c,
                   Account.Long_Term_Debtor__c, Account.Total_AR__c, Account.Credit_Limit__c
            FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];

        // ─ 단계 점수
        s.stageScore = STAGE_SCORE.containsKey(opp.StageName) ? STAGE_SCORE.get(opp.StageName) : 5;
        if (opp.StageName == '실주') s.riskFactors.add('실주된 거래');
        if (opp.StageName == '발굴') s.riskFactors.add('초기 단계 — 견적 작성 필요');

        // ─ 활동 점수
        Datetime since = Datetime.now().addDays(-14);
        Integer activityCount = 0;
        activityCount += [SELECT count() FROM Task  WHERE WhatId = :opportunityId AND CreatedDate >= :since];
        activityCount += [SELECT count() FROM Event WHERE WhatId = :opportunityId AND CreatedDate >= :since];

        if (activityCount >= 6)      s.activityScore = 20;
        else if (activityCount >= 3) s.activityScore = 15;
        else if (activityCount >= 1) s.activityScore = 8;
        else {
            s.activityScore = 0;
            s.riskFactors.add('최근 14일 활동 0건 (응답 지연 우려)');
        }

        // ─ Account 점수
        Decimal credit = (opp.Account != null && opp.Account.External_Credit_Score__c != null)
            ? opp.Account.External_Credit_Score__c : 0;
        if (credit >= 700)      s.accountScore = 15;
        else if (credit >= 500) s.accountScore = 10;
        else if (credit > 0)    s.accountScore = 5;
        else                    s.accountScore = 8; // 미상 — 중립값

        if (opp.Account != null && opp.Account.Long_Term_Debtor__c == true) {
            s.accountScore = Math.max(0, s.accountScore - 5);
            s.riskFactors.add('Account 장기미수 보유');
        }
        if (opp.Account != null && String.isBlank(opp.Account.Business_Number__c)) {
            s.riskFactors.add('사업자번호 미입력 — 단계 게이트 미충족');
        }

        // ─ Engagement 점수
        s.engagementScore = 0;
        List<Quote> quotes = [
            SELECT Id, Status, Sent_Date__c, Last_Opened_At__c
            FROM Quote WHERE OpportunityId = :opportunityId
        ];
        if (!quotes.isEmpty()) {
            s.engagementScore = 5;
            for (Quote q : quotes) {
                if (q.Sent_Date__c != null) { s.engagementScore += 5; break; }
            }
            for (Quote q : quotes) {
                if (q.Last_Opened_At__c != null) { s.engagementScore += 5; break; }
            }
        } else {
            s.riskFactors.add('연결된 견적 없음 — 견적 작성 필요');
        }
        if (s.engagementScore > 15) s.engagementScore = 15;

        s.total = s.stageScore + s.activityScore + s.accountScore + s.engagementScore;
        if (s.total > 100) s.total = 100;
        if (s.total < 0)   s.total = 0;
        return s;
    }
}
