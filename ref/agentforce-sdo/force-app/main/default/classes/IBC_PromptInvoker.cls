/**
 * @description Prompt Template 호출 추상화. ConnectApi 의존성을 단위 테스트에서 분리하기 위한 SAM 인터페이스.
 *              프로덕션 구현은 {@link BC_PromptInvoker}, 테스트용은 {@link BC_PromptInvokerMock}.
 *
 * @group AutoLeadByBC
 */
public interface IBC_PromptInvoker {
    /**
     * @description 멀티모달: ContentDocument 1건의 이미지를 입력으로 호출.
     * @param contentDocumentId 명함 이미지 ContentDocument Id
     * @return 파싱된 BC_LLMResponse
     */
    BC_LLMResponse invokeForImage(Id contentDocumentId);

    /**
     * @description 텍스트 전용: 기존 raw_text 기반 재매핑 호출. (Phase 2에서 활성화)
     * @param rawText 이전 추출의 raw_text
     * @return 파싱된 BC_LLMResponse
     */
    BC_LLMResponse invokeForText(String rawText);
}
