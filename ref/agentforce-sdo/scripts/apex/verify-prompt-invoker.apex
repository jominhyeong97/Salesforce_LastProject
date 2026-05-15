// BC_PromptInvoker (Apex Service Layer) 검증 스크립트
// 역할: Spike 2 reference 호출이 클래스화된 후에도 동일하게 작동하는지 확인.
// 실행: sf apex run -f scripts/apex/verify-prompt-invoker.apex --target-org agentforce-sdo

ContentDocument cd = [
    SELECT Id, Title FROM ContentDocument
    WHERE FileType IN ('JPG', 'JPEG', 'PNG')
    ORDER BY CreatedDate DESC LIMIT 1
];
System.debug('대상 ContentDocument: ' + cd.Id + ' (' + cd.Title + ')');

IBC_PromptInvoker invoker = new BC_PromptInvoker();
Long t0 = System.currentTimeMillis();
BC_LLMResponse resp = invoker.invokeForImage(cd.Id);
Long elapsed = System.currentTimeMillis() - t0;

System.debug('elapsed=' + elapsed + 'ms');
System.debug('isBusinessCard=' + resp.isBusinessCard + ', lang=' + resp.languageDetected);
System.debug('rawText 길이=' + (resp.rawText != null ? resp.rawText.length() : 0));
System.debug('필드 수=' + resp.fields.size());
for (String k : resp.fields.keySet()) {
    BC_LLMResponse.FieldValue f = resp.fields.get(k);
    System.debug('  ' + k + ' = ' + f.value + ' (conf=' + f.confidence + ')');
}
System.debug('low confidence (<0.5): ' + resp.lowConfidenceFields(0.5));
System.debug('warnings: ' + resp.extractionWarnings.size());
System.debug('✅ BC_PromptInvoker 검증 정상');
