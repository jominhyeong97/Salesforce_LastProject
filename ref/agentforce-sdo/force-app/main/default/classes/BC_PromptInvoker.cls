/**
 * @description `BC_Extract_AndMap` Prompt Template 호출의 프로덕션 구현.
 *              ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate를 통해 멀티모달 LLM 호출.
 *
 * @group AutoLeadByBC
 *
 * <h3>호출 패턴 (Spike 2 검증, v66)</h3>
 * <ul>
 *   <li>capability       : '' (빈 문자열)</li>
 *   <li>inputParams      : Input:ContentDocument → WrappedValue(value=Map{'Id' → cdId})</li>
 *   <li>applicationName  : 'PromptBuilderPreview'</li>
 *   <li>isPreview        : false</li>
 * </ul>
 *
 * @see IBC_PromptInvoker
 * @see BC_LLMResponse
 */
public with sharing class BC_PromptInvoker implements IBC_PromptInvoker {
    @TestVisible private static final String TEMPLATE_DEV_NAME = 'BC_Extract_AndMap';
    @TestVisible private static final String CAPABILITY = '';
    @TestVisible private static final String APPLICATION_NAME = 'PromptBuilderPreview';

    /**
     * @description 명함 이미지 ContentDocument 1건을 입력으로 멀티모달 Prompt Template 호출.
     *              응답 JSON을 BC_LLMResponse DTO로 파싱해 반환.
     *
     * @param contentDocumentId 명함 이미지가 저장된 ContentDocument의 Id (필수)
     * @return 파싱된 BC_LLMResponse. isBusinessCard=false면 명함이 아닌 이미지로 분류된 것.
     * @throws BC_PromptInvokerException null 입력 / null 응답 / generation error / 파싱 실패 시
     */
    public BC_LLMResponse invokeForImage(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new BC_PromptInvokerException('contentDocumentId is required');
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();

        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = APPLICATION_NAME;
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
        wv.value = new Map<String, Object>{ 'Id' => contentDocumentId };
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:ContentDocument' => wv
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_DEV_NAME, CAPABILITY, input);

        if (resp == null) {
            throw new BC_PromptInvokerException('LLM returned null response');
        }
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new BC_PromptInvokerException(
                'LLM generation error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new BC_PromptInvokerException('LLM returned empty generations');
        }
        return BC_LLMResponse.fromJson(resp.generations[0].text);
    }

    /**
     * @description 텍스트 전용 재매핑 호출. Phase 2의 BC_ReMap_FromText Prompt Template과 함께 도입 예정.
     * @param rawText 이전 추출에서 얻은 raw_text 문자열
     * @return BC_LLMResponse
     * @throws BC_PromptInvokerException 항상 발생 (미구현)
     */
    public BC_LLMResponse invokeForText(String rawText) {
        throw new BC_PromptInvokerException(
            'invokeForText is not yet implemented (deferred to Phase 2)');
    }

    /** @description Prompt Template 호출 / 파싱 실패를 표현하는 체크드 예외. */
    public class BC_PromptInvokerException extends Exception {}
}
