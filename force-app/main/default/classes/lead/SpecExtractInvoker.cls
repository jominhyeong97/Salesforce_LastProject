/**
 * SpecExtractInvoker — SpecExtract Prompt 의 ConnectApi 라이브 호출 분리.
 * BusinessLicensePromptInvoker 패턴 — 코드 커버리지 임계 격리(라이브 블록 unit test 불가).
 * Service 가 호출, test 는 mock 우회.
 * @group Lead
 */
public with sharing class SpecExtractInvoker {

    @TestVisible private static String mockJsonResponse;
    @TestVisible private static String mockExceptionMessage;

    public static String invoke(String templateName, String subject, String body) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new SpecExtractInvokerException(mockExceptionMessage);
            return mockJsonResponse;
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = 'PromptBuilderPreview';
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wSub = new ConnectApi.WrappedValue();
        wSub.value = (subject == null) ? '' : subject;
        ConnectApi.WrappedValue wBody = new ConnectApi.WrappedValue();
        wBody.value = body;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Subject' => wSub,
            'Input:Body' => wBody
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, '', input);

        if (resp == null) throw new SpecExtractInvokerException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new SpecExtractInvokerException(
                'LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new SpecExtractInvokerException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    public class SpecExtractInvokerException extends Exception {}
}
