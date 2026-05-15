@isTest
private class BC_LLMResponseTest {

    private static String validBody() {
        return JSON.serialize(new Map<String, Object>{
            'raw_text' => 'TEST | 홍길동 | hong@test.com',
            'is_business_card' => true,
            'language_detected' => 'ko',
            'fields' => new Map<String, Object>{
                'company' => new Map<String, Object>{ 'value' => 'TestCo', 'confidence' => 1.0 },
                'last_name' => new Map<String, Object>{ 'value' => '홍길동', 'confidence' => 0.95 },
                'email' => new Map<String, Object>{ 'value' => '', 'confidence' => 0 }
            },
            'extraction_warnings' => new List<String>{ 'email 누락' }
        });
    }

    @isTest static void fromJsonParsesAllExpectedFields() {
        BC_LLMResponse r = BC_LLMResponse.fromJson(validBody());
        System.assertEquals('TEST | 홍길동 | hong@test.com', r.rawText);
        System.assertEquals(true, r.isBusinessCard);
        System.assertEquals('ko', r.languageDetected);
        System.assertEquals(3, r.fields.size());
        System.assertEquals('TestCo', r.fields.get('company').value);
        System.assertEquals(1.0, r.fields.get('company').confidence);
        System.assertEquals('', r.fields.get('email').value);
        System.assertEquals(0, r.fields.get('email').confidence);
        System.assertEquals(1, r.extractionWarnings.size());
        System.assertEquals('email 누락', r.extractionWarnings[0]);
    }

    @isTest static void fromJsonRejectsBlankBody() {
        Boolean caught = false;
        try {
            BC_LLMResponse.fromJson('');
        } catch (BC_LLMResponse.BC_LLMResponseException e) {
            caught = true;
        }
        System.assert(caught, 'BC_LLMResponseException 기대');
    }

    @isTest static void fromJsonRejectsInvalidJson() {
        Boolean caught = false;
        try {
            BC_LLMResponse.fromJson('not json');
        } catch (BC_LLMResponse.BC_LLMResponseException e) {
            caught = true;
            System.assert(e.getMessage().contains('not valid JSON'));
        }
        System.assert(caught);
    }

    @isTest static void fromJsonHandlesMissingOptionalKeys() {
        String body = JSON.serialize(new Map<String, Object>{
            'raw_text' => 'x',
            'is_business_card' => false,
            'language_detected' => 'unknown'
            // fields, extraction_warnings 누락
        });
        BC_LLMResponse r = BC_LLMResponse.fromJson(body);
        System.assertEquals(false, r.isBusinessCard);
        System.assertEquals(0, r.fields.size());
        System.assertEquals(0, r.extractionWarnings.size());
    }

    @isTest static void lowConfidenceFieldsReturnsBlankAndBelowThreshold() {
        BC_LLMResponse r = BC_LLMResponse.fromJson(validBody());
        List<String> low = r.lowConfidenceFields(0.5);
        System.assert(low.contains('email'), 'email은 빈 value (confidence=0)이라 low');
        System.assert(!low.contains('company'), 'company는 confidence=1.0이라 low가 아님');
        System.assert(!low.contains('last_name'), 'last_name은 confidence=0.95이라 low가 아님');
    }

    @isTest static void lowConfidenceFieldsRespectsThreshold() {
        BC_LLMResponse r = BC_LLMResponse.fromJson(validBody());
        // last_name(0.95)보다 높은 threshold 1.0이면 last_name도 low로 잡혀야
        List<String> low = r.lowConfidenceFields(1.0);
        System.assert(low.contains('last_name'));
    }
}
