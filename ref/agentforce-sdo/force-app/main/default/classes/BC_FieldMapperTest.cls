@isTest
private class BC_FieldMapperTest {

    private static BC_LLMResponse buildResp() {
        BC_LLMResponse r = new BC_LLMResponse();
        r.rawText = 'sample raw text';
        r.isBusinessCard = true;
        r.languageDetected = 'ko';
        r.fields.put('company',          new BC_LLMResponse.FieldValue('TestCo', 1.0));
        r.fields.put('department',       new BC_LLMResponse.FieldValue('영업1팀', 0.9));
        r.fields.put('title',            new BC_LLMResponse.FieldValue('대표이사', 1.0));
        r.fields.put('last_name',        new BC_LLMResponse.FieldValue('홍길동', 1.0));
        r.fields.put('email',            new BC_LLMResponse.FieldValue('hong@test.com', 1.0));
        r.fields.put('mobile_phone',     new BC_LLMResponse.FieldValue('M. 010-1234-5678', 0.95));
        r.fields.put('phone',            new BC_LLMResponse.FieldValue('Tel: 02-123-4567', 1.0));
        r.fields.put('fax',              new BC_LLMResponse.FieldValue('', 0));
        r.fields.put('website',          new BC_LLMResponse.FieldValue('https://test.com', 1.0));
        r.fields.put('address',          new BC_LLMResponse.FieldValue('06170 서울시 강남구', 1.0));
        r.fields.put('lead_source_hint', new BC_LLMResponse.FieldValue('', 0));
        r.extractionWarnings.add('fax 누락');
        return r;
    }

    @isTest static void applyExtractionPopulatesAllFields() {
        BC_FieldMapper m = new BC_FieldMapper();
        BusinessCard__c card = new BusinessCard__c();

        m.applyExtraction(card, buildResp());

        System.assertEquals('Mapped', card.Status__c);
        System.assertEquals('TestCo', card.Company__c);
        System.assertEquals('영업1팀', card.Department__c);
        System.assertEquals('홍길동', card.Last_Name__c);
        System.assertEquals('M. 010-1234-5678', card.Mobile_Phone__c, 'verbatim copy 유지 (label prefix 보존)');
        System.assertEquals('https://test.com', card.Website__c);
        System.assertEquals('ko', card.Detected_Language__c);
        System.assertEquals('sample raw text', card.Raw_OCR_Text__c);
        System.assertEquals('fax 누락', card.Extraction_Warnings__c);
        System.assertEquals(null, card.Fax__c, '빈 value는 null로');
        System.assertEquals(null, card.Lead_Source_Hint__c, '빈 value는 null로');
        System.assert(card.Extraction_Confidence_JSON__c.contains('"company":1.0'));
    }

    @isTest static void applyExtractionWithNullsIsNoop() {
        BC_FieldMapper m = new BC_FieldMapper();
        BusinessCard__c card = new BusinessCard__c();
        m.applyExtraction(null, buildResp());
        m.applyExtraction(card, null);
        System.assertEquals(null, card.Company__c, 'null resp → 변경 없음');
    }

    @isTest static void buildLeadCopiesAllExpectedFields() {
        BC_FieldMapper m = new BC_FieldMapper();
        BusinessCard__c card = new BusinessCard__c();
        m.applyExtraction(card, buildResp());
        // BusinessCard에 Id가 없어도 Lead 생성은 돼야 함 (insert 전 단계)
        Lead lead = m.buildLead(card);

        System.assertEquals('TestCo', lead.Company);
        System.assertEquals('홍길동', lead.LastName);
        System.assertEquals('대표이사', lead.Title);
        System.assertEquals('hong@test.com', lead.Email);
        System.assertEquals('M. 010-1234-5678', lead.MobilePhone);
        System.assertEquals('Tel: 02-123-4567', lead.Phone);
        System.assertEquals('06170 서울시 강남구', lead.Street);
        System.assertEquals(UserInfo.getUserId(), lead.OwnerId);
    }

    @isTest static void buildLeadFallsBackWhenCompanyOrLastNameMissing() {
        BC_FieldMapper m = new BC_FieldMapper();
        BusinessCard__c card = new BusinessCard__c();  // 모든 필드 비어 있음
        Lead lead = m.buildLead(card);
        System.assertEquals('[Unknown Company]', lead.Company);
        System.assertEquals('[Unknown]', lead.LastName);
    }

    @isTest static void confidenceJsonSerializesAllFields() {
        BC_FieldMapper m = new BC_FieldMapper();
        String confBody = m.confidenceJson(buildResp());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(confBody);
        System.assertEquals(11, parsed.size());
        System.assertEquals(1.0, parsed.get('company'));
    }

    @isTest static void confidenceJsonHandlesNull() {
        BC_FieldMapper m = new BC_FieldMapper();
        System.assertEquals('{}', m.confidenceJson(null));
    }
}
