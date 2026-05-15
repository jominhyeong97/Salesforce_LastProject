/**
 * QuoteTriggerHandler — Quote 자동화 룰 (D37).
 *
 *   Rule 1 (before insert): Account.BillingAddress / ShippingAddress / 1차 Contact 정보를
 *                            Quote 신규 레코드에 자동 복사. AE 입력 부담 0.
 *   Rule 2 (after update):  Status '수락' 으로 전이 시 QuoteLineItem 을
 *                            OpportunityLineItem 으로 자동 복사 (수동 sync 대체).
 *                            → Won 전이 시 OrderTriggerHandler 가 OrderItem 까지 자동 복사 (Day 9 #1).
 *
 * 참고 — Quote.IsSyncing 표준 필드는 platform read-only 라 Apex 에서 set 불가.
 * 직접 OpportunityLineItem 복사로 동일 비즈니스 효과 확보.
 *
 * @group Quote
 */
public with sharing class QuoteTriggerHandler {

    // ─────────────────────────────────────────────────────────────────────
    // Rule 1 — before insert: Account 주소·Contact 복사
    // ─────────────────────────────────────────────────────────────────────

    public static void handleBeforeInsert(List<Quote> newList) {
        if (newList == null || newList.isEmpty()) return;

        // Quote.AccountId 는 before insert 시점에 SF 가 채우지 않음 — Opp 에서 derive
        Set<Id> oppIds = new Set<Id>();
        for (Quote q : newList) {
            if (q.AccountId == null && q.OpportunityId != null) oppIds.add(q.OpportunityId);
        }
        Map<Id, Id> oppToAcc = new Map<Id, Id>();
        if (!oppIds.isEmpty()) {
            for (Opportunity o : [SELECT Id, AccountId FROM Opportunity WHERE Id IN :oppIds]) {
                oppToAcc.put(o.Id, o.AccountId);
            }
        }

        Set<Id> accIds = new Set<Id>();
        Map<Id, Id> quoteToDerivedAcc = new Map<Id, Id>();
        Integer idx = 0;
        for (Quote q : newList) {
            Id derivedAcc = q.AccountId != null ? q.AccountId : oppToAcc.get(q.OpportunityId);
            if (derivedAcc != null) {
                accIds.add(derivedAcc);
                // 임시 식별자로 record 의 위치 인덱스 사용 (Id 없음)
                quoteToDerivedAcc.put((Id) null, derivedAcc); // placeholder, unused
            }
            idx++;
        }
        if (accIds.isEmpty()) return;

        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, Name, Phone,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
            FROM Account WHERE Id IN :accIds
        ]);

        Map<Id, Contact> primaryContact = new Map<Id, Contact>();
        for (Contact c : [
            SELECT Id, AccountId, Email, Phone
            FROM Contact
            WHERE AccountId IN :accIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!primaryContact.containsKey(c.AccountId)) {
                primaryContact.put(c.AccountId, c);
            }
        }

        for (Quote q : newList) {
            Id resolvedAccId = q.AccountId != null ? q.AccountId : oppToAcc.get(q.OpportunityId);
            if (resolvedAccId == null) continue;
            Account a = accMap.get(resolvedAccId);
            if (a == null) continue;

            if (String.isBlank(q.BillingStreet))     q.BillingStreet     = a.BillingStreet;
            if (String.isBlank(q.BillingCity))       q.BillingCity       = a.BillingCity;
            if (String.isBlank(q.BillingState))      q.BillingState      = a.BillingState;
            if (String.isBlank(q.BillingPostalCode)) q.BillingPostalCode = a.BillingPostalCode;
            if (String.isBlank(q.BillingCountry))    q.BillingCountry    = a.BillingCountry;

            if (String.isBlank(q.ShippingStreet))     q.ShippingStreet     = a.ShippingStreet;
            if (String.isBlank(q.ShippingCity))       q.ShippingCity       = a.ShippingCity;
            if (String.isBlank(q.ShippingState))      q.ShippingState      = a.ShippingState;
            if (String.isBlank(q.ShippingPostalCode)) q.ShippingPostalCode = a.ShippingPostalCode;
            if (String.isBlank(q.ShippingCountry))    q.ShippingCountry    = a.ShippingCountry;

            if (String.isBlank(q.BillingName))  q.BillingName  = a.Name;
            if (String.isBlank(q.ShippingName)) q.ShippingName = a.Name;

            Contact c = primaryContact.get(resolvedAccId);
            if (c != null) {
                if (q.ContactId == null)    q.ContactId = c.Id;
                if (String.isBlank(q.Email)) q.Email = c.Email;
                if (String.isBlank(q.Phone)) q.Phone = c.Phone;
            }
            if (String.isBlank(q.Phone)) q.Phone = a.Phone;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Rule 2 — after update: Status='수락' 전이 시 QuoteLineItem → OpportunityLineItem
    // ─────────────────────────────────────────────────────────────────────

    public static void handleAfterUpdate(List<Quote> newList, Map<Id, Quote> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) return;

        Set<Id> acceptedQuoteIds = new Set<Id>();
        for (Quote q : newList) {
            Quote oldQ = oldMap.get(q.Id);
            if (oldQ == null) continue;
            Boolean justAccepted = isAccepted(q.Status) && !isAccepted(oldQ.Status);
            if (justAccepted) acceptedQuoteIds.add(q.Id);
        }
        if (acceptedQuoteIds.isEmpty()) return;

        // Quote → Opp 매핑
        Map<Id, Id> quoteToOpp = new Map<Id, Id>();
        for (Quote q : [SELECT Id, OpportunityId FROM Quote WHERE Id IN :acceptedQuoteIds]) {
            if (q.OpportunityId != null) quoteToOpp.put(q.Id, q.OpportunityId);
        }
        if (quoteToOpp.isEmpty()) return;

        // 각 Opp 의 기존 OpportunityLineItem 삭제
        Set<Id> oppIds = new Set<Id>(quoteToOpp.values());
        List<OpportunityLineItem> existingOli = [
            SELECT Id FROM OpportunityLineItem WHERE OpportunityId IN :oppIds
        ];
        if (!existingOli.isEmpty()) delete existingOli;

        // QuoteLineItem 조회 후 OpportunityLineItem 으로 복사
        List<OpportunityLineItem> toInsert = new List<OpportunityLineItem>();
        for (QuoteLineItem qli : [
            SELECT Id, QuoteId, Product2Id, PricebookEntryId, Quantity, UnitPrice,
                   Discount, Description, ServiceDate
            FROM QuoteLineItem
            WHERE QuoteId IN :acceptedQuoteIds
        ]) {
            Id oppId = quoteToOpp.get(qli.QuoteId);
            if (oppId == null) continue;
            OpportunityLineItem oli = new OpportunityLineItem(
                OpportunityId    = oppId,
                PricebookEntryId = qli.PricebookEntryId,
                Quantity         = qli.Quantity,
                UnitPrice        = qli.UnitPrice,
                Discount         = qli.Discount,
                Description      = qli.Description,
                ServiceDate      = qli.ServiceDate
            );
            toInsert.add(oli);
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }

    @TestVisible
    private static Boolean isAccepted(String status) {
        return status == '수락' || status == 'Accepted';
    }
}
