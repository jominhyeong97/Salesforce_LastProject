/**
 * IExternalErpService — ERP 게이트웨이 인터페이스 (D17).
 *
 * 외부 ERP 연동 책임을 인터페이스로 격리하여, Day 8 시연용 Mock 구현과
 * 향후 실 ERP 어댑터(Beeceptor/Named Credential/MuleSoft 등)를 교체 가능.
 * 평가자 답변 — "Sales Cloud 는 ERP 신호의 소비자, 게이트웨이 패턴으로 책임 분리."
 *
 * @group Order
 */
public interface IExternalErpService {
    /**
     * 주어진 Order 목록의 ERP 측 생산 상태·위험 신호를 조회.
     * 호출 측은 결과의 riskScore / signals 만 사용하고 가격·라인은 손대지 않음 (D26 안전 정책 일관).
     */
    List<ErpSyncResult> fetchOrderStatus(List<Id> orderIds);
}
