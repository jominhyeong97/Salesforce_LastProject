/**
 * BusinessLicenseLLMResponse — Prompt Builder 응답 JSON을 표현하는 DTO + 파서.
 *
 * 스키마 (BusinessLicenseExtract prompt template과 1:1 대응):
 *   {
 *     "businessNumber": "",
 *     "companyName":    "",
 *     "ceoName":        "",
 *     "address":        "",
 *     "raw_text":       ""
 *   }
 */
public with sharing class BusinessLicenseLLMResponse {

    public String businessNumber;
    public String companyName;
    public String ceoName;
    public String address;
    public String rawText;

    /** 원본 LLM JSON 문자열 보존 — LWC 표시용. */
    public String originalJson;

    public BusinessLicenseLLMResponse() {}

    /**
     * Prompt Builder 응답 본문(JSON) → DTO.
     * @param body generations[0].text — 마크다운 펜스/주석 없는 순수 JSON 문자열 기대
     * @throws BusinessLicenseLLMResponseException blank/잘못된 JSON
     */
    public static BusinessLicenseLLMResponse fromJson(String body) {
        if (String.isBlank(body)) {
            throw new BusinessLicenseLLMResponseException('Empty response body');
        }
        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            throw new BusinessLicenseLLMResponseException(
                'Response is not valid JSON: ' + e.getMessage() +
                ' (앞 200자: ' + body.substring(0, Math.min(200, body.length())) + ')');
        }

        BusinessLicenseLLMResponse out = new BusinessLicenseLLMResponse();
        out.businessNumber = stringFrom(raw.get('businessNumber'));
        out.companyName    = stringFrom(raw.get('companyName'));
        out.ceoName        = stringFrom(raw.get('ceoName'));
        out.address        = stringFrom(raw.get('address'));
        out.rawText        = stringFrom(raw.get('raw_text'));
        out.originalJson   = body;
        return out;
    }

    private static String stringFrom(Object v) {
        return v == null ? null : String.valueOf(v);
    }

    /** 4개 필드(businessNumber, companyName, ceoName, address)가 모두 blank인지. */
    public Boolean isAllBlank() {
        return String.isBlank(businessNumber)
            && String.isBlank(companyName)
            && String.isBlank(ceoName)
            && String.isBlank(address);
    }

    /** LWC 표시용 평면 Map. raw_text 포함. */
    public Map<String, String> asExtractedMap() {
        return new Map<String, String>{
            'businessNumber' => businessNumber,
            'companyName'    => companyName,
            'ceoName'        => ceoName,
            'address'        => address,
            'rawText'        => rawText
        };
    }

    public class BusinessLicenseLLMResponseException extends Exception {}
}
