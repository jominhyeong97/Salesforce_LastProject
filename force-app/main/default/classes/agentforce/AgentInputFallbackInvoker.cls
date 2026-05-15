/**
 * AgentInputFallbackInvoker — AgentInputFallback Prompt 라이브 호출 분리 (커버리지 격리).
 * @group Agentforce
 */
public with sharing class AgentInputFallbackInvoker {

    @TestVisible private static String mockResponse;
    @TestVisible private static String mockExceptionMessage;

    public static String invoke(String utterance) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new AgentInputFallbackException(mockExceptionMessage);
            return mockResponse;
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = 'PromptBuilderPreview';
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue w = new ConnectApi.WrappedValue();
        w.value = utterance == null ? '' : utterance;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Utterance' => w
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                'AgentInputFallback', '', input);

        if (resp == null) throw new AgentInputFallbackException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new AgentInputFallbackException(
                'LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new AgentInputFallbackException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    public class AgentInputFallbackException extends Exception {}
}
