/**
 * AgentRouterInvoker — AgentRouter Prompt 라이브 호출 분리 (D30 커버리지 격리).
 * 입력: utterance + contextHint, 출력: tool 선택 JSON (LLM 원본 문자열).
 * @group Agentforce
 */
public with sharing class AgentRouterInvoker {

    @TestVisible private static String mockResponse;
    @TestVisible private static String mockExceptionMessage;

    public static String invoke(String utterance, String contextHint) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new AgentRouterException(mockExceptionMessage);
            return mockResponse;
        }

        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg =
            new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = 'PromptBuilderPreview';
        input.additionalConfig = cfg;
        input.isPreview = false;

        ConnectApi.WrappedValue wvU = new ConnectApi.WrappedValue();
        wvU.value = utterance == null ? '' : utterance;
        ConnectApi.WrappedValue wvC = new ConnectApi.WrappedValue();
        wvC.value = contextHint == null ? '' : contextHint;

        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Utterance'   => wvU,
            'Input:ContextHint' => wvC
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                'AgentRouter', '', input);

        if (resp == null) throw new AgentRouterException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new AgentRouterException(
                'LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new AgentRouterException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    public class AgentRouterException extends Exception {}
}
