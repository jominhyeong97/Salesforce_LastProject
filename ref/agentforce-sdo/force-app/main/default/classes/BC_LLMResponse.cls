/**
 * @description Prompt Template `BC_Extract_AndMap` 응답 JSON을 표현하는 DTO + 파서.
 *              스키마는 Prompt Template의 출력 JSON과 1:1로 대응한다.
 *
 * @group AutoLeadByBC
 *
 * @see BC_PromptInvoker
 * @see BC_FieldMapper
 */
public with sharing class BC_LLMResponse {
    /** @description 명함의 모든 visible text를 reading order로 합친 원본. " | "로 구분. */
    public String rawText;
    /** @description 이미지가 명함으로 분류됐는지 여부. false면 매핑/Lead 생성 스킵. */
    public Boolean isBusinessCard;
    /** @description LLM이 감지한 언어 코드 (예: 'ko', 'en'). */
    public String languageDetected;
    /** @description 11개 필드의 value+confidence. key는 Prompt Template 스키마와 일치. */
    public Map<String, FieldValue> fields;
    /** @description LLM이 보낸 한국어 경고 메시지 목록 (누락 사유 등). */
    public List<String> extractionWarnings;

    /** @description 단일 필드의 추출값 + confidence(0.0~1.0) 쌍. */
    public class FieldValue {
        public String value;
        public Decimal confidence;
        public FieldValue() {}
        public FieldValue(String v, Decimal c) { this.value = v; this.confidence = c; }
    }

    public BC_LLMResponse() {
        this.fields = new Map<String, FieldValue>();
        this.extractionWarnings = new List<String>();
    }

    /**
     * @description Prompt Template 응답 본문 문자열을 파싱해 DTO로 변환.
     *              파싱 실패 시 본문 앞 200자를 예외 메시지에 포함시켜 디버깅 지원.
     *
     * @param body Prompt Template 응답 generations[0].text (JSON 문자열)
     * @return 파싱된 BC_LLMResponse
     * @throws BC_LLMResponseException body가 비어 있거나 JSON 파싱 실패 시
     */
    public static BC_LLMResponse fromJson(String body) {
        if (String.isBlank(body)) {
            throw new BC_LLMResponseException('Empty response body');
        }
        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            throw new BC_LLMResponseException(
                'Response is not valid JSON: ' + e.getMessage() +
                ' (앞 200자: ' + body.substring(0, Math.min(200, body.length())) + ')');
        }

        BC_LLMResponse out = new BC_LLMResponse();
        out.rawText = (String) raw.get('raw_text');
        out.isBusinessCard = (Boolean) raw.get('is_business_card');
        out.languageDetected = (String) raw.get('language_detected');

        Object rawFields = raw.get('fields');
        if (rawFields instanceof Map<String, Object>) {
            Map<String, Object> fieldMap = (Map<String, Object>) rawFields;
            for (String k : fieldMap.keySet()) {
                Map<String, Object> f = (Map<String, Object>) fieldMap.get(k);
                out.fields.put(k, new FieldValue(
                    (String) f.get('value'),
                    f.get('confidence') != null ? (Decimal) f.get('confidence') : 0
                ));
            }
        }

        Object rawWarn = raw.get('extraction_warnings');
        if (rawWarn instanceof List<Object>) {
            for (Object w : (List<Object>) rawWarn) {
                out.extractionWarnings.add(String.valueOf(w));
            }
        }
        return out;
    }

    /**
     * @description 빈 값이거나 confidence &lt; threshold 인 필드명 목록 반환.
     * @param threshold 기준 confidence (예: 0.5)
     * @return 미흡한 필드명 목록 (예: ['website','title'])
     */
    public List<String> lowConfidenceFields(Decimal threshold) {
        List<String> result = new List<String>();
        for (String k : fields.keySet()) {
            FieldValue fv = fields.get(k);
            if (String.isBlank(fv.value) || fv.confidence < threshold) {
                result.add(k);
            }
        }
        return result;
    }

    /** @description 응답 본문 파싱 실패를 표현하는 체크드 예외. */
    public class BC_LLMResponseException extends Exception {}
}
