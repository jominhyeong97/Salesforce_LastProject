/**
 * SpecExtractService — EMAIL RFQ 본문·제목 → 6필드 JSON 추출 (FR-LEAD-002).
 *
 * CallMemoExtract 패턴 + D26 stripCodeFences. RFQ 메일 컨텍스트(긴 본문·서명·정중체) 특화 Prompt.
 *
 * @group Lead
 */
public with sharing class SpecExtractService {

    private static final String[] FIELD_KEYS = new String[]{
        'company', 'contactName', 'phone', 'partName', 'quantity', 'requestedDate'
    };

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'SpecExtract';

    @TestVisible public static String lastSource;

    /**
     * RFQ 메일 분석 — Subject + Body 컨텍스트.
     * AI 실패 또는 빈 응답 시 CallMemoExtractService(body) 로 fallback.
     */
    public static Map<String, String> extract(String subject, String body) {
        Map<String, String> r = emptyResult();
        if (String.isBlank(body)) {
            lastSource = 'empty';
            return r;
        }

        try {
            String aiJson = SpecExtractInvoker.invoke(TEMPLATE_DEV_NAME, subject, body);
            if (String.isBlank(aiJson)) throw new SpecExtractException('Empty AI body');
            Map<String, String> ai = parseAiJson(aiJson);
            if (isAllBlank(ai)) throw new SpecExtractException('AI all-blank');
            lastSource = 'ai';
            // AI 가 못 찾은 필드는 CallMemoExtract(정규식 fallback 포함) 로 보강
            Map<String, String> backup = CallMemoExtractService.extract(body);
            for (String k : FIELD_KEYS) {
                String v = ai.get(k);
                r.put(k, String.isBlank(v) ? backup.get(k) : v);
            }
            return r;
        } catch (Exception e) {
            lastSource = 'fallback';
            return CallMemoExtractService.extract(body);
        }
    }

    @TestVisible
    private static Map<String, String> parseAiJson(String body) {
        String clean = stripCodeFences(body);
        if (String.isBlank(clean)) throw new SpecExtractException('Empty AI body');
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(clean);
        Map<String, String> r = emptyResult();
        for (String k : FIELD_KEYS) {
            Object v = raw.get(k);
            r.put(k, v == null ? '' : String.valueOf(v));
        }
        return r;
    }

    @TestVisible
    private static String stripCodeFences(String body) {
        if (String.isBlank(body)) return body;
        String trimmed = body.trim();
        if (!trimmed.startsWith('`')) return trimmed;
        Pattern p = Pattern.compile('(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$');
        Matcher m = p.matcher(trimmed);
        return m.matches() ? m.group(1) : trimmed;
    }

    private static Boolean isAllBlank(Map<String, String> m) {
        for (String k : FIELD_KEYS) {
            if (String.isNotBlank(m.get(k))) return false;
        }
        return true;
    }

    private static Map<String, String> emptyResult() {
        Map<String, String> r = new Map<String, String>();
        for (String k : FIELD_KEYS) r.put(k, '');
        return r;
    }

    public class SpecExtractException extends Exception {}
}
