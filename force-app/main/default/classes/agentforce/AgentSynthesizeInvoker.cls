/**
 * AgentSynthesizeInvoker — AgentSynthesize Prompt 라이브 호출 분리 (D30 커버리지 격리).
 * 입력: utterance + toolName + actionResultJson, 출력: 한국어 자연어 응답 1단락.
 * @group Agentforce
 */
public with sharing class AgentSynthesizeInvoker {

    @TestVisible private static String mockResponse;
    @TestVisible private static String mockExceptionMessage;

    public static String invoke(String utterance, String toolName, String actionResultJson) {
        if (Test.isRunningTest()) {
            if (mockExceptionMessage != null) throw new AgentSynthesizeException(mockExceptionMessage);
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
        ConnectApi.WrappedValue wvT = new ConnectApi.WrappedValue();
        wvT.value = toolName == null ? '' : toolName;
        ConnectApi.WrappedValue wvR = new ConnectApi.WrappedValue();
        wvR.value = actionResultJson == null ? '' : actionResultJson;

        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Utterance'    => wvU,
            'Input:ToolName'     => wvT,
            'Input:ActionResult' => wvR
        };

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation resp =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                'AgentSynthesize', '', input);

        if (resp == null) throw new AgentSynthesizeException('LLM null response');
        if (resp.generationErrors != null && !resp.generationErrors.isEmpty()) {
            throw new AgentSynthesizeException(
                'LLM error: ' + JSON.serialize(resp.generationErrors[0]));
        }
        if (resp.generations == null || resp.generations.isEmpty()) {
            throw new AgentSynthesizeException('LLM empty generations');
        }
        return resp.generations[0].text;
    }

    public class AgentSynthesizeException extends Exception {}
}
