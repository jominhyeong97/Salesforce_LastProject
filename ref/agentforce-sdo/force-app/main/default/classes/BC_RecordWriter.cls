/**
 * @description BusinessCard / Lead / ContentDocumentLink에 대한 모든 DML을 캡슐화.
 *              "DML은 이 클래스를 통해서만"이라는 단일 책임 경계를 유지한다.
 *
 * @group AutoLeadByBC
 *
 * <h3>설계 원칙</h3>
 * <ul>
 *   <li>모든 DML은 이 클래스를 통해서만 일어난다.</li>
 *   <li>Lead INSERT은 표준 Duplicate Rule을 우회 (`AllowSave=true`) — "누락 &gt; 중복" 원칙.</li>
 *   <li>매핑/계산은 하지 않는다 (그건 {@link BC_FieldMapper}의 책임).</li>
 * </ul>
 */
public with sharing class BC_RecordWriter {

    /**
     * @description 신규 BusinessCard__c를 Status='Extracting'으로 INSERT 후 반환.
     * @return 새로 생성된 BusinessCard__c (Id 채워짐)
     */
    public BusinessCard__c insertExtracting() {
        BusinessCard__c card = new BusinessCard__c(Status__c = 'Extracting');
        insert card;
        return card;
    }

    /**
     * @description 명함 레코드 ↔ 이미지 ContentDocument 연결 (ShareType=V, Visibility=InternalUsers).
     * @param cardId            BusinessCard__c Id
     * @param contentDocumentId 이미지 ContentDocument Id
     */
    public void linkContentDocument(Id cardId, Id contentDocumentId) {
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = cardId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
    }

    /**
     * @description Lead 레코드 ↔ 이미지 ContentDocument 연결 — Lead 페이지에서도 명함 이미지 미리보기.
     *              이미 BusinessCard에 동일 ContentDocument가 연결돼 있어도 Lead에 별도 ContentDocumentLink가 필요.
     *
     * @param leadId            Lead Id
     * @param contentDocumentId 이미지 ContentDocument Id
     */
    public void linkContentDocumentToLead(Id leadId, Id contentDocumentId) {
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = leadId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );
    }

    /**
     * @description BC_FieldMapper가 in-place 채워 넣은 BusinessCard를 UPDATE.
     * @param card 매핑 완료된 BusinessCard__c
     */
    public void updateMapped(BusinessCard__c card) {
        update card;
    }

    /**
     * @description Lead INSERT — 표준 Duplicate Rule 매칭 시에도 통과 (`AllowSave=true`).
     *              결과적으로 lead.Id가 in-place로 채워진다.
     *
     * @param lead 새로 INSERT할 Lead 인스턴스
     * @throws System.DmlException Database.SaveResult가 실패한 경우
     */
    public void insertLeadAllowingDuplicates(Lead lead) {
        Database.DMLOptions dlo = new Database.DMLOptions();
        dlo.DuplicateRuleHeader.AllowSave = true;
        dlo.DuplicateRuleHeader.RunAsCurrentUser = true;
        Database.SaveResult sr = Database.insert(lead, dlo);
        if (!sr.isSuccess()) {
            throw new System.DmlException(sr.getErrors()[0].getMessage());
        }
    }

    /**
     * @description 명함을 Failed로 마킹 (Status, Failure_Reason, Processing_Duration_Ms 동시 처리).
     * @param card        Failed로 표시할 BusinessCard__c
     * @param failureCode 실패 분류 (예: 'LLM_FAILURE'). null 가능.
     * @param message     사용자 표시용 메시지
     * @param durationMs  처리 경과 ms
     */
    public void markFailed(BusinessCard__c card, String failureCode, String message, Long durationMs) {
        card.Status__c = 'Failed';
        card.Failure_Reason__c = (failureCode != null ? '[' + failureCode + '] ' : '') + message;
        card.Processing_Duration_Ms__c = durationMs;
        update card;
    }

    /**
     * @description 명함을 LeadCreated로 마킹 (Status, Lead Lookup, Processing_Duration_Ms 동시 처리).
     * @param card       성공 마킹 대상 BusinessCard__c
     * @param leadId     생성된 Lead의 Id
     * @param durationMs 처리 경과 ms
     */
    public void markLeadCreated(BusinessCard__c card, Id leadId, Long durationMs) {
        card.Status__c = 'LeadCreated';
        card.Lead__c = leadId;
        card.Processing_Duration_Ms__c = durationMs;
        update card;
    }
}
