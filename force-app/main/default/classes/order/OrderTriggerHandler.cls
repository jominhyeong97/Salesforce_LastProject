/**
 * OrderTriggerHandler — Order 트리거 핸들러.
 *
 * Case A (2026-05-12 결정) — 수주 → Order 자동 생성 시 견적 라인을 OrderItem 으로 자동 복사.
 *
 *  흐름:
 *   1) Order.Opportunity__c (custom lookup, 표준 OpportunityId 가 이 Org 미활성화) 가 있는 Order 만 처리
 *   2) Opportunity.SyncedQuoteId 우선, fallback Status='수락' Quote (LastModifiedDate DESC LIMIT 1)
 *   3) QuoteLineItem → OrderItem 복사
 *      - PricebookEntryId/Quantity 그대로
 *      - effectiveUnitPrice = UnitPrice - (Discount_Amount__c / Quantity)  → 할인 분배 (Quote 총액과 일치)
 *   4) D26 안전 정책 — AI/시스템이 가격 임의 변경 금지, Quote 확정 가격 그대로 승계
 *
 * Idempotent — Order 가 이미 OrderItem 을 가지면 추가 복사 안 함 (수동 라인 보존).
 *
 * @group Order
 */
public with sharing class OrderTriggerHandler {

    @TestVisible private static final String QUOTE_ACCEPTED_STATUS = '수락';

    public static void copyQuoteLinesOnInsert(List<Order> newOrders) {
        if (newOrders == null || newOrders.isEmpty()) return;

        // 1. Opportunity__c 가 있는 Order 만 수집 (표준 OpportunityId 가 이 Org 미활성)
        Map<Id, Order> oppIdToOrder = new Map<Id, Order>();
        for (Order o : newOrders) {
            if (o.Opportunity__c != null) {
                oppIdToOrder.put(o.Opportunity__c, o);
            }
        }
        if (oppIdToOrder.isEmpty()) return;

        // 2. Opp 의 SyncedQuoteId 조회 (1순위)
        Map<Id, Id> oppToQuote = new Map<Id, Id>();
        for (Opportunity opp : [
            SELECT Id, SyncedQuoteId
            FROM Opportunity
            WHERE Id IN :oppIdToOrder.keySet()
        ]) {
            if (opp.SyncedQuoteId != null) {
                oppToQuote.put(opp.Id, opp.SyncedQuoteId);
            }
        }

        // 3. SyncedQuoteId 없는 Opp 는 Status='수락' Quote 로 fallback
        Set<Id> missingSync = new Set<Id>();
        for (Id oppId : oppIdToOrder.keySet()) {
            if (!oppToQuote.containsKey(oppId)) missingSync.add(oppId);
        }
        if (!missingSync.isEmpty()) {
            for (Quote q : [
                SELECT Id, OpportunityId
                FROM Quote
                WHERE OpportunityId IN :missingSync AND Status = :QUOTE_ACCEPTED_STATUS
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!oppToQuote.containsKey(q.OpportunityId)) {
                    oppToQuote.put(q.OpportunityId, q.Id);  // 최신 수락본
                }
            }
        }
        if (oppToQuote.isEmpty()) return;

        // 4. QuoteLineItem 조회
        Set<Id> quoteIds = new Set<Id>(oppToQuote.values());
        List<QuoteLineItem> qlis = [
            SELECT Id, QuoteId, PricebookEntryId, Quantity, UnitPrice, Discount_Amount__c
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
        ];
        if (qlis.isEmpty()) return;

        // 5. Quote → Order 역매핑
        Map<Id, Id> quoteToOpp = new Map<Id, Id>();
        for (Id oppId : oppToQuote.keySet()) {
            quoteToOpp.put(oppToQuote.get(oppId), oppId);
        }

        // 6. OrderItem 생성 (할인 분배 — effectiveUnitPrice)
        List<OrderItem> newItems = new List<OrderItem>();
        for (QuoteLineItem qli : qlis) {
            Id oppId = quoteToOpp.get(qli.QuoteId);
            if (oppId == null) continue;
            Order targetOrder = oppIdToOrder.get(oppId);
            if (targetOrder == null) continue;

            Decimal unitPrice = qli.UnitPrice == null ? 0 : qli.UnitPrice;
            Decimal qty = qli.Quantity == null ? 0 : qli.Quantity;
            Decimal discount = qli.Discount_Amount__c == null ? 0 : qli.Discount_Amount__c;
            Decimal effective = unitPrice;
            if (discount > 0 && qty > 0) {
                effective = unitPrice - (discount / qty);
                if (effective < 0) effective = 0;
            }

            newItems.add(new OrderItem(
                OrderId          = targetOrder.Id,
                PricebookEntryId = qli.PricebookEntryId,
                Quantity         = qty,
                UnitPrice        = effective
            ));
        }

        if (!newItems.isEmpty()) {
            insert newItems;
        }
    }
}
