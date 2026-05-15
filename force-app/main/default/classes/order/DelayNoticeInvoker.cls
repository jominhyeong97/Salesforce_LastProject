/**
 * DelayNoticeInvoker — DelayNotice Prompt 의 ConnectApi 라이브 호출 분리 (커버리지 격리).
 * SpecExtractInvoker / BusinessLicensePromptInvoker 패턴 차용.
 * @group Order
 */
public with sharing class DelayNoticeInvoker {

    @TestVisible private static String mockJsonResponse;
    @TestVisible private static String mockExceptionMessage;

    public static String invoke(String templateName, Id orderId, String additionalContext) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new DelayNoticeInvokerException(mockExceptionMessage);
            return mockJsonResponse;
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = 'PromptBuilderPreview';
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wOrder = new ConnectApi.WrappedValue();
        wOrder.value = new Map<String, Object>{ 'Id' => orderId };
        ConnectApi.WrappedValue wCtx = new ConnectApi.WrappedValue();
        wCtx.value = (additionalContext == null) ? '' : additionalContext;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:OrderRecord' => wOrder,
            'Input:AdditionalContext' => wCtx
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, '', input);

        if (resp == null) throw new DelayNoticeInvokerException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new DelayNoticeInvokerException(
                'LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new DelayNoticeInvokerException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    public class DelayNoticeInvokerException extends Exception {}
}
