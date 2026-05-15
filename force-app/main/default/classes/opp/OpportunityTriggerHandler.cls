/**
 * OpportunityTriggerHandler
 *  - before insert: Pricebook2Id 누락 시 Standard Pricebook 자동 할당
 *  - before update: Stage 전환 시 StageGateService 게이트 enforce (FR-OPP-001)
 *  - after update : '수주' 전환 시 Order 자동 생성 (FR-ORDER-001, Day 9)
 *                   생성된 Order 는 Case A OrderTrigger 가 QuoteLineItem → OrderItem 자동 복사
 *
 * Bulkified — Stage 변경된 Opp 일괄 SOQL 후 룰 평가/Order 생성.
 *
 * @group Opp
 */
public with sharing class OpportunityTriggerHandler {

    @TestVisible private static final String WON_STAGE = '수주';

    // ─────────────────────────────────────────────────────────────────────
    // BEFORE INSERT — Pricebook 자동 할당
    // (downstream Quote.Pricebook2Id 상속 → quoteBuilder 제품 옵션 로드 보장,
    //  handleAfterUpdate 의 Won→Order 자동 생성 가드 통과 보장)
    // ─────────────────────────────────────────────────────────────────────

    public static void handleBeforeInsert(List<Opportunity> newList) {
        if (newList == null || newList.isEmpty()) return;

        Boolean anyMissing = false;
        for (Opportunity o : newList) {
            if (o.Pricebook2Id == null) { anyMissing = true; break; }
        }
        if (!anyMissing) return;

        Id stdId = resolveStandardPricebookId();
        for (Opportunity o : newList) {
            if (o.Pricebook2Id == null) o.Pricebook2Id = stdId;
        }
    }

    // Apex 테스트 컨텍스트에서는 Pricebook2 SOQL 이 비어 보이므로 Test API 분기.
    // 프로덕션 경로에서 Standard Pricebook 부재 시엔 표준 QueryException 으로 fail-loud.
    @TestVisible
    private static Id resolveStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE LIMIT 1].Id;
    }

    // ─────────────────────────────────────────────────────────────────────
    // BEFORE UPDATE — 게이트
    // ─────────────────────────────────────────────────────────────────────

    public static void handleBeforeUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        if (newList == null || oldMap == null) return;

        Map<Id, String> stageTransitions = new Map<Id, String>(); // oppId → fromStage
        for (Opportunity o : newList) {
            Opportunity old = oldMap.get(o.Id);
            if (old != null && o.StageName != old.StageName) {
                stageTransitions.put(o.Id, old.StageName);
            }
        }
        if (stageTransitions.isEmpty()) return;

        Map<Id, Opportunity> details = new Map<Id, Opportunity>([
            SELECT Id, StageName, Description, Promised_Delivery_Date__c,
                   AccountId, Account.Business_Number__c,
                   (SELECT Id FROM OpportunityContactRoles)
            FROM Opportunity
            WHERE Id IN :stageTransitions.keySet()
        ]);

        for (Opportunity o : newList) {
            if (!stageTransitions.containsKey(o.Id)) continue;
            Opportunity detail = details.get(o.Id);
            if (detail == null) continue;
            String fromStage = stageTransitions.get(o.Id);
            String toStage = o.StageName;

            List<StageGateService.GateRule> failures =
                StageGateService.evaluateFailures(detail, fromStage, toStage);

            if (!failures.isEmpty()) {
                String msg = '단계 전환 게이트 미충족 (' + fromStage + ' → ' + toStage + '):';
                for (StageGateService.GateRule g : failures) {
                    msg += '\n  - ' + g.label + ' (' + g.hintText + ')';
                }
                o.addError(msg);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // AFTER UPDATE — 수주 → Order 자동 생성
    // ─────────────────────────────────────────────────────────────────────

    public static void handleAfterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        if (newList == null || oldMap == null) return;

        // 1. '수주' 로 전환된 Opp 만 수집 (이미 수주였던 건 제외)
        Set<Id> wonOppIds = new Set<Id>();
        for (Opportunity o : newList) {
            Opportunity old = oldMap.get(o.Id);
            if (old != null && o.StageName == WON_STAGE && old.StageName != WON_STAGE) {
                wonOppIds.add(o.Id);
            }
        }
        if (wonOppIds.isEmpty()) return;

        // 2. 이미 Order 가진 Opp 제외 (idempotent — 재실행 안전)
        Set<Id> oppsWithOrder = new Set<Id>();
        for (Order existing : [
            SELECT Opportunity__c FROM Order WHERE Opportunity__c IN :wonOppIds
        ]) {
            if (existing.Opportunity__c != null) {
                oppsWithOrder.add(existing.Opportunity__c);
            }
        }

        Set<Id> needsOrder = new Set<Id>(wonOppIds);
        needsOrder.removeAll(oppsWithOrder);
        if (needsOrder.isEmpty()) return;

        // 3. Opp 상세 (AccountId, Pricebook2Id, 약속 납기일) 조회 — D38: EndDate 복사용
        Map<Id, Opportunity> details = new Map<Id, Opportunity>([
            SELECT Id, AccountId, Pricebook2Id, Promised_Delivery_Date__c
            FROM Opportunity WHERE Id IN :needsOrder
        ]);

        // 4. Order 생성 — Order insert 이후 OrderTrigger 가 라인 복사 (Case A)
        List<Order> toCreate = new List<Order>();
        Integer year = Date.today().year();
        for (Id oppId : needsOrder) {
            Opportunity opp = details.get(oppId);
            if (opp == null || opp.AccountId == null || opp.Pricebook2Id == null) continue;

            String oppIdStr = String.valueOf(opp.Id);
            String poSuffix = oppIdStr.substring(oppIdStr.length() - 4);

            toCreate.add(new Order(
                AccountId            = opp.AccountId,
                Opportunity__c       = opp.Id,
                EffectiveDate        = Date.today(),
                EndDate              = opp.Promised_Delivery_Date__c,  // D38: 약속 납기일 승계
                Status               = 'Draft',
                Pricebook2Id         = opp.Pricebook2Id,
                PoNumber             = 'PO-' + year + '-W' + poSuffix,
                Production_Status__c = 'Pending'
            ));
        }

        if (!toCreate.isEmpty()) {
            insert toCreate;
        }
    }
}
