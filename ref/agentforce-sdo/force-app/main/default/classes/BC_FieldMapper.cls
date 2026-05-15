/**
 * @description LLM 응답을 BusinessCard / Lead 객체로 in-memory 매핑하는 책임만 갖는다.
 *              DML은 절대 수행하지 않는다 (그건 {@link BC_RecordWriter}의 책임).
 *
 * @group AutoLeadByBC
 *
 * <h3>책임 경계</h3>
 * <ul>
 *   <li>매핑(필드 복사) + 직렬화(confidence JSON)만 한다.</li>
 *   <li>1차 릴리즈는 verbatim copy. 정규화(stripPhoneLabel 등)는 Phase 2 후속.</li>
 * </ul>
 *
 * @see BC_LLMResponse
 * @see BC_RecordWriter
 */
public with sharing class BC_FieldMapper {

    /**
     * @description LLM 응답을 BusinessCard 인스턴스에 in-place로 채워 넣는다 (Status='Mapped').
     *              card나 resp가 null이면 no-op.
     *
     * @param card BusinessCard__c 인스턴스 (in-place 수정됨, DML 안 함)
     * @param resp 파싱 완료된 LLM 응답
     */
    public void applyExtraction(BusinessCard__c card, BC_LLMResponse resp) {
        if (card == null || resp == null) return;
        Map<String, BC_LLMResponse.FieldValue> f = resp.fields;

        card.Status__c                 = 'Mapped';
        card.Raw_OCR_Text__c           = resp.rawText;
        card.Detected_Language__c      = resp.languageDetected;
        card.Extraction_Warnings__c    = String.join(resp.extractionWarnings, '\n');
        card.Extraction_Confidence_JSON__c = confidenceJson(resp);

        card.Company__c          = pick(f, 'company');
        card.Department__c       = pick(f, 'department');
        card.Title__c            = pick(f, 'title');
        card.Last_Name__c        = pick(f, 'last_name');
        card.Email__c            = pick(f, 'email');
        card.Mobile_Phone__c     = pick(f, 'mobile_phone');
        card.Phone__c            = pick(f, 'phone');
        card.Fax__c              = pick(f, 'fax');
        card.Website__c          = pick(f, 'website');
        card.Address__c          = pick(f, 'address');
        card.Lead_Source_Hint__c = pick(f, 'lead_source_hint');
    }

    /**
     * @description BusinessCard 추출값을 Lead 표준 필드로 매핑해 새 Lead 인스턴스 생성.
     *              Company / LastName이 비어 있으면 Lead 표준 required 필드 검증 통과를 위해 placeholder 사용.
     *
     * @param card 매핑 완료된 BusinessCard__c
     * @return DML 직전 상태의 Lead 인스턴스 (Source_BusinessCard__c가 card.Id로 채워짐)
     */
    public Lead buildLead(BusinessCard__c card) {
        return new Lead(
            Company     = String.isNotBlank(card.Company__c) ? card.Company__c : '[Unknown Company]',
            LastName    = String.isNotBlank(card.Last_Name__c) ? card.Last_Name__c : '[Unknown]',
            Title       = card.Title__c,
            Email       = card.Email__c,
            Phone       = card.Phone__c,
            MobilePhone = card.Mobile_Phone__c,
            Fax         = card.Fax__c,
            Website     = card.Website__c,
            Street      = card.Address__c,
            LeadSource  = card.Lead_Source_Hint__c,
            OwnerId     = UserInfo.getUserId(),
            Source_BusinessCard__c = card.Id
        );
    }

    /**
     * @description 필드별 confidence를 JSON 문자열로 직렬화. fetchResult에서 missingFields 산정 시 사용.
     * @param resp BC_LLMResponse
     * @return 예: '{"company":1.0,"website":0.0,"title":0.85}'
     */
    public String confidenceJson(BC_LLMResponse resp) {
        Map<String, Object> conf = new Map<String, Object>();
        if (resp != null && resp.fields != null) {
            for (String k : resp.fields.keySet()) {
                conf.put(k, resp.fields.get(k).confidence);
            }
        }
        return JSON.serialize(conf);
    }

    private String pick(Map<String, BC_LLMResponse.FieldValue> f, String key) {
        if (f == null) return null;
        BC_LLMResponse.FieldValue fv = f.get(key);
        return (fv != null && String.isNotBlank(fv.value)) ? fv.value : null;
    }
}
