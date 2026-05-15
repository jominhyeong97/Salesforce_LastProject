/**
 * CallMemoExtractService — PHONE Lead 통화메모 → 폼 필드 추출 (FR-LEAD-006).
 *
 * Day 7 P1 OppInsight 패턴 차용 — Prompt Builder Template 우선 호출, 실패 시 한국어 정규식 fallback.
 *
 * 추출 키 (6): company / contactName / phone / partName / quantity / requestedDate
 * 안전 정책 (D26) — LLM 응답 코드 펜스(```json...```) 자동 제거, 마크다운 강건성 확보.
 *
 * @group Lead
 */
public with sharing class CallMemoExtractService {

    private static final String[] FIELD_KEYS = new String[]{
        'company', 'contactName', 'contactTitle', 'phone', 'partName', 'quantity', 'requestedDate'
    };

    @TestVisible private static final String TEMPLATE_DEV_NAME = 'CallMemoExtract';
    @TestVisible private static final String CAPABILITY        = '';
    @TestVisible private static final String APPLICATION_NAME  = 'PromptBuilderPreview';

    /** 테스트 우회 — AI 응답 시뮬 (JSON 문자열). */
    @TestVisible private static String mockJsonResponse;
    /** 테스트 우회 — AI 예외 시뮬 (fallback 강제). */
    @TestVisible private static String mockExceptionMessage;
    /** AE 가 보는 마지막 호출의 소스 — 'ai' | 'fallback'. UI 배지/디버그용. */
    @TestVisible public static String lastSource;

    @AuraEnabled
    public static Map<String, String> extract(String memo) {
        Map<String, String> r = emptyResult();
        if (String.isBlank(memo)) {
            lastSource = 'empty';
            return r;
        }

        try {
            String aiJson = invokePromptForMemo(memo);
            Map<String, String> ai = parseAiJson(aiJson);
            // 빈 응답(모든 필드 blank)이면 fallback
            if (isAllBlank(ai)) throw new CallMemoExtractException('AI returned all-blank');
            lastSource = 'ai';
            // AI 누락 필드는 regex 로 보강
            Map<String, String> regex = extractByRegex(memo);
            for (String k : FIELD_KEYS) {
                String v = ai.get(k);
                r.put(k, String.isBlank(v) ? regex.get(k) : v);
            }
            return r;
        } catch (Exception e) {
            lastSource = 'fallback';
            return extractByRegex(memo);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Prompt Builder 호출 (Day 7 P1 OppInsight 패턴, D26 stripCodeFences 적용)
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static String invokePromptForMemo(String memo) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new CallMemoExtractException(mockExceptionMessage);
            return mockJsonResponse != null
                ? mockJsonResponse
                : '{"company":"","contactName":"","phone":"","partName":"","quantity":"","requestedDate":""}';
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = memo;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Memo' => wv
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);

        if (resp == null) throw new CallMemoExtractException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new CallMemoExtractException('LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new CallMemoExtractException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    @TestVisible
    private static Map<String, String> parseAiJson(String body) {
        String clean = stripCodeFences(body);
        if (String.isBlank(clean)) throw new CallMemoExtractException('Empty AI body');
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(clean);
        Map<String, String> r = emptyResult();
        for (String k : FIELD_KEYS) {
            Object v = raw.get(k);
            r.put(k, v == null ? '' : String.valueOf(v));
        }
        return r;
    }

    /** D26 일관 — LLM 응답이 ```json...``` 으로 감싸지면 벗겨낸다. */
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

    // ─────────────────────────────────────────────────────────────────────
    // Fallback: 한국어 정규식 (LLM 장애 시 시연 안정성 확보)
    // ─────────────────────────────────────────────────────────────────────

    @TestVisible
    private static Map<String, String> extractByRegex(String memo) {
        Map<String, String> r = emptyResult();
        if (String.isBlank(memo)) return r;

        // 1. 전화번호
        Matcher mPhone = Pattern.compile('01[016789][- ]?\\d{3,4}[- ]?\\d{4}').matcher(memo);
        if (mPhone.find()) r.put('phone', mPhone.group());

        // 2. 수량 (숫자 + 단위)
        Matcher mQty = Pattern.compile('(\\d+)\\s*(개|EA|ea|pcs|PCS)').matcher(memo);
        if (mQty.find()) r.put('quantity', mQty.group(1));

        // 3. 회사명 — 첫 토큰
        Matcher mCo = Pattern.compile('^[^\\s,]+').matcher(memo.trim());
        if (mCo.find()) r.put('company', mCo.group());

        // 4. 담당자 / 직급 (한국식 표기 보존 — 성 단독 금지, 호칭 씨/님 제거)
        //   Pattern A (직급 있음): "김 대리"/"김사장"/"박민수 과장"/"김사장님" → name=원문(님 제거), title=직급
        //   Pattern B (호칭만):    "김국진씨"/"이수정님"                     → name=풀네임, title=""
        String surnameClass = '김이박정최강조윤장임한오서신권황안홍송문배백남심노하주구유전';
        Matcher mTitle = Pattern.compile(
            '([' + surnameClass + '])([가-힣]{1,2})?(\\s?)(대리|과장|차장|부장|팀장|이사|상무|전무|사장|대표)(님)?'
        ).matcher(memo);
        if (mTitle.find()) {
            String surname = mTitle.group(1);
            String given   = mTitle.group(2);     // 가운데 이름 (없을 수 있음)
            String sep     = mTitle.group(3);     // 성과 직급 사이 공백
            String title   = mTitle.group(4);
            // 풀네임(성+이름) 있으면 이름만 분리, 없으면 성+직급 통째로(성 단독 금지)
            String name = (String.isNotBlank(given))
                ? (surname + given)
                : (surname + sep + title);
            r.put('contactName', name);
            r.put('contactTitle', title);
        } else {
            Matcher mFull = Pattern.compile(
                '([' + surnameClass + '])([가-힣]{1,2})(씨|님)'
            ).matcher(memo);
            if (mFull.find()) {
                r.put('contactName', mFull.group(1) + mFull.group(2));
                // contactTitle 은 비워둠 — 직급 정보 없음
            }
        }

        // 5. 부품명
        Matcher mPart = Pattern.compile(
            '(베어링|단조품|정밀가공품|주물품|판금품|볼트|너트|샤프트|기어)\\s?([A-Za-z0-9\\-]+)?'
        ).matcher(memo);
        if (mPart.find()) {
            String partFull = mPart.group(1);
            String mod = mPart.group(2);
            if (mod != null && mod.length() > 0 && !Pattern.matches('\\d.*', mod)) {
                partFull += ' ' + mod;
            }
            r.put('partName', partFull);
        }

        // 6. 납기
        Matcher mDate = Pattern.compile(
            '(다음달|이번달|이번주|다음주|내일|모레|\\d+월\\s?말?|\\d+일까지|\\d+주\\s?내)\\s?(말|초)?(까지|중)?'
        ).matcher(memo);
        if (mDate.find()) r.put('requestedDate', mDate.group());

        return r;
    }

    public class CallMemoExtractException extends Exception {}
}
