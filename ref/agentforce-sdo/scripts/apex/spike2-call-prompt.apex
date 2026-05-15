// =====================================================================
// Spike 2 검증 완료 — BC_Extract_AndMap Prompt Template Apex 호출 reference
//
// 검증된 호출 형식 (v66.0):
//   메서드   : ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate
//   capability : '' (빈 문자열)
//   inputParams : { 'Input:ContentDocument' → WrappedValue(value=Map{'Id': cdId}) }
//   isPreview : false
//   applicationName : 'PromptBuilderPreview' (추후 'Default' 검토)
//
// 잘못된 형태 (Resolution 실패) — 참고:
//   - WrappedValue.value = SObject record         → "Invalid input value: [ContentDocument (...)]"
//   - WrappedValue.value = Id 문자열               → "Invalid input value: 069..."
//   - WrappedValue.value = new ContentDocument(Id=...) → "Invalid input value: {Id=...}"
//   ✅ WrappedValue.value = new Map<String,Object>{'Id' => cdId} 만 통과
//
// 실행: sf apex run -f scripts/apex/spike2-call-prompt.apex --target-org agentforce-sdo
// =====================================================================

// 1. 호출 대상 ContentDocument 1건 조회 (필요 시 'Id cdId = 069XXX...' 로 직접 지정)
List<ContentDocument> cds = [
    SELECT Id, Title FROM ContentDocument
    WHERE FileType IN ('JPG', 'JPEG', 'PNG')
    ORDER BY CreatedDate DESC LIMIT 1
];
if (cds.isEmpty()) {
    System.debug(LoggingLevel.ERROR, '❌ ContentDocument 없음. 명함 이미지를 먼저 ORG에 업로드하세요.');
    return;
}
Id cdId = cds[0].Id;
System.debug('호출 대상 ContentDocument: ' + cdId + ' (' + cds[0].Title + ')');

// 2. Prompt Template 호출 입력 구성
ConnectApi.EinsteinPromptTemplateGenerationsInput genInput =
    new ConnectApi.EinsteinPromptTemplateGenerationsInput();
ConnectApi.EinsteinLlmAdditionalConfigInput cfg = new ConnectApi.EinsteinLlmAdditionalConfigInput();
cfg.applicationName = 'PromptBuilderPreview';
genInput.additionalConfig = cfg;
genInput.isPreview = false;

ConnectApi.WrappedValue cdWrap = new ConnectApi.WrappedValue();
cdWrap.value = new Map<String, Object>{ 'Id' => cdId };  // ⬅︎ 핵심: Map 형태로 감싸야 resolution 통과
genInput.inputParams = new Map<String, ConnectApi.WrappedValue>{
    'Input:ContentDocument' => cdWrap
};

// 3. 호출 + 시간 측정
Long startMs = System.currentTimeMillis();
ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
    ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
        'BC_Extract_AndMap',
        '',
        genInput
    );
Long elapsedMs = System.currentTimeMillis() - startMs;
System.debug('호출 완료 ' + elapsedMs + 'ms, requestId=' + resp.requestId);

// 4. 응답 검증
if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
    for (Integer i = 0; i < resp.generationErrors.size(); i++) {
        System.debug(LoggingLevel.ERROR, 'generationError[' + i + ']: ' +
            JSON.serialize(resp.generationErrors[i]));
    }
    return;
}
if (resp.generations == null || resp.generations.isEmpty()) {
    System.debug(LoggingLevel.ERROR, '❌ generations 비어있음');
    return;
}

String body = resp.generations[0].text;
System.debug('=== 응답 ===');
System.debug(body);

// 5. JSON 파싱 검증
Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
System.debug('is_business_card=' + parsed.get('is_business_card') +
    ', language=' + parsed.get('language_detected'));

Map<String, Object> fields = (Map<String, Object>) parsed.get('fields');
for (String fname : fields.keySet()) {
    Map<String, Object> f = (Map<String, Object>) fields.get(fname);
    System.debug('  ' + fname + ' = ' + f.get('value') + ' (conf=' + f.get('confidence') + ')');
}
List<Object> warnings = (List<Object>) parsed.get('extraction_warnings');
System.debug('warnings: ' + warnings.size() + '개');
System.debug('✅ Spike 2 reference 호출 정상');
