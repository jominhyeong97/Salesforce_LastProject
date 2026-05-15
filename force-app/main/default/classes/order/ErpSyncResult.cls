/**
 * ErpSyncResult — ERP 동기화 1건 결과 DTO.
 * IExternalErpService 가 반환, OrderErpSyncService 가 Order 필드로 사상.
 * 내부 DTO 로 @AuraEnabled 없음 (LWC 노출용 DTO 는 OrderErpSyncService.SyncOutcome).
 *
 * D38 Phase 2 (2026-05-12) — expectedShipDate / delayReason 추가.
 *   약속 납기(Order.EndDate) 대비 ERP 측 실제 예상 출고일 및 지연 사유.
 *   null expectedShipDate = "미정" (사유 명시).
 *
 * @group Order
 */
public class ErpSyncResult {
    public Id orderId;
    public Integer riskScore;            // 0~100
    public String productionStatus;      // ERP 측 보고 상태 (정보 전달용)
    public DateTime syncedAt;
    public List<String> signals;         // 진단 메시지 한국어
    public Date expectedShipDate;        // D38 Phase 2: ERP 예상 출고일 (null = 미정)
    public String delayReason;           // D38 Phase 2: 지연/미정 사유 한국어

    public ErpSyncResult() {
        this.signals = new List<String>();
    }
}
