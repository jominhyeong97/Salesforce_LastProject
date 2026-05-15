/**
 * @description 단위/통합 테스트용 Mock. {@link AutoLeadByBC_Service}의 @TestVisible static instance에
 *              주입해 LLM 호출을 가짜 응답으로 대체한다.
 *
 * @group AutoLeadByBC
 *
 * @example
 * BC_PromptInvokerMock mock = new BC_PromptInvokerMock();
 * mock.responseToReturn = buildHappyResponse();
 * AutoLeadByBC_Service.invoker = mock;
 *
 * @see IBC_PromptInvoker
 */
@isTest
public class BC_PromptInvokerMock implements IBC_PromptInvoker {
    /** @description invokeForImage / invokeForText가 정상 반환할 응답. */
    public BC_LLMResponse responseToReturn;
    /** @description 이 값이 set 되어 있으면 두 메서드 모두 던진다. */
    public Exception exceptionToThrow;
    /** @description invokeForImage 호출 횟수 누적. */
    public Integer imageCallCount = 0;
    /** @description invokeForText 호출 횟수 누적. */
    public Integer textCallCount = 0;
    /** @description 마지막 invokeForImage 호출 인자 보관. */
    public Id lastContentDocumentId;
    /** @description 마지막 invokeForText 호출 인자 보관. */
    public String lastRawText;

    public BC_LLMResponse invokeForImage(Id contentDocumentId) {
        imageCallCount++;
        lastContentDocumentId = contentDocumentId;
        if (exceptionToThrow != null) throw exceptionToThrow;
        return responseToReturn;
    }

    public BC_LLMResponse invokeForText(String rawText) {
        textCallCount++;
        lastRawText = rawText;
        if (exceptionToThrow != null) throw exceptionToThrow;
        return responseToReturn;
    }
}
