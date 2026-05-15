// =====================================================================
// Phase 1 Vertical Slice E2E 검증
// 흐름: ContentDocument → BC_PromptInvoker → BusinessCard__c INSERT/UPDATE → Lead INSERT
// 실행: sf apex run -f scripts/apex/e2e-vertical-slice.apex --target-org agentforce-sdo
// =====================================================================

// 1. 명함 ContentDocument 1건
ContentDocument cd = [
    SELECT Id, Title FROM ContentDocument
    WHERE FileType IN ('JPG', 'JPEG', 'PNG')
    ORDER BY CreatedDate DESC LIMIT 1
];
System.debug('명함: ' + cd.Id + ' (' + cd.Title + ')');

// 2. BusinessCard__c 신규 (Status=Extracting)
Long t0 = System.currentTimeMillis();
BusinessCard__c card = new BusinessCard__c(Status__c = 'Extracting');
insert card;
System.debug('BusinessCard 신규 생성: ' + card.Id);

// 3. 명함 ↔ 이미지 ContentDocumentLink 연결
ContentDocumentLink cdl = new ContentDocumentLink(
    ContentDocumentId = cd.Id,
    LinkedEntityId = card.Id,
    ShareType = 'V',
    Visibility = 'InternalUsers'
);
insert cdl;

// 4. LLM 호출
IBC_PromptInvoker invoker = new BC_PromptInvoker();
BC_LLMResponse resp;
try {
    resp = invoker.invokeForImage(cd.Id);
} catch (Exception e) {
    card.Status__c = 'Failed';
    card.Failure_Reason__c = e.getMessage();
    update card;
    System.debug(LoggingLevel.ERROR, '❌ LLM 실패: ' + e.getMessage());
    return;
}

// 5. is_business_card == false 처리
if (resp.isBusinessCard != true) {
    card.Status__c = 'Failed';
    card.Failure_Reason__c = 'Image is not a business card.';
    card.Raw_OCR_Text__c = resp.rawText;
    update card;
    System.debug(LoggingLevel.ERROR, '❌ not a business card');
    return;
}

// 6. BusinessCard UPDATE (Status=Mapped, 모든 추출 필드 + 메타)
Map<String, BC_LLMResponse.FieldValue> f = resp.fields;
card.Status__c = 'Mapped';
card.Raw_OCR_Text__c = resp.rawText;
card.Detected_Language__c = resp.languageDetected;
card.Extraction_Warnings__c = String.join(resp.extractionWarnings, '\n');

// 6-1. 추출 필드 매핑 (verbatim 그대로 — 정규화는 후속)
card.Company__c          = (f.containsKey('company'))          ? f.get('company').value          : null;
card.Department__c       = (f.containsKey('department'))       ? f.get('department').value       : null;
card.Title__c            = (f.containsKey('title'))            ? f.get('title').value            : null;
card.Last_Name__c        = (f.containsKey('last_name'))        ? f.get('last_name').value        : null;
card.Email__c            = (f.containsKey('email'))            ? f.get('email').value            : null;
card.Mobile_Phone__c     = (f.containsKey('mobile_phone'))     ? f.get('mobile_phone').value     : null;
card.Phone__c            = (f.containsKey('phone'))            ? f.get('phone').value            : null;
card.Fax__c              = (f.containsKey('fax'))              ? f.get('fax').value              : null;
card.Website__c          = (f.containsKey('website'))          ? f.get('website').value          : null;
card.Address__c          = (f.containsKey('address'))          ? f.get('address').value          : null;
card.Lead_Source_Hint__c = (f.containsKey('lead_source_hint')) ? f.get('lead_source_hint').value : null;

// 6-2. 신뢰도를 JSON으로 직렬화
Map<String, Object> confJson = new Map<String, Object>();
for (String k : f.keySet()) {
    confJson.put(k, f.get(k).confidence);
}
card.Extraction_Confidence_JSON__c = JSON.serialize(confJson);
card.LLM_Model_Used__c = 'sfdc_ai__DefaultGPT41Mini';

update card;
System.debug('BusinessCard UPDATE → Status=Mapped, ' + f.size() + ' 필드');

// 7. Lead INSERT (verbatim 명함 필드 → Lead 표준 필드 매핑)
Lead lead = new Lead(
    Company    = String.isNotBlank(card.Company__c) ? card.Company__c : '[Unknown Company]',
    LastName   = String.isNotBlank(card.Last_Name__c) ? card.Last_Name__c : '[Unknown]',
    Title      = card.Title__c,
    Email      = card.Email__c,
    Phone      = card.Phone__c,
    MobilePhone = card.Mobile_Phone__c,
    Fax        = card.Fax__c,
    Website    = card.Website__c,
    Street     = card.Address__c,         // 단일 필드라 Street에 일괄 저장
    LeadSource = card.Lead_Source_Hint__c,
    Source_BusinessCard__c = card.Id
);
insert lead;
System.debug('Lead 신규 생성: ' + lead.Id);

// 8. BusinessCard 마무리 (Status=LeadCreated, Lead Lookup 채움)
card.Status__c = 'LeadCreated';
card.Lead__c = lead.Id;
card.Processing_Duration_Ms__c = System.currentTimeMillis() - t0;
update card;

// 9. 결과 요약
System.debug('=== ✅ Vertical Slice 통과 ===');
System.debug('BusinessCard Id : ' + card.Id);
System.debug('Lead Id         : ' + lead.Id);
System.debug('Total 소요(ms)  : ' + card.Processing_Duration_Ms__c);
System.debug('LowConfidence   : ' + resp.lowConfidenceFields(0.5));
System.debug('Warnings        : ' + resp.extractionWarnings);
