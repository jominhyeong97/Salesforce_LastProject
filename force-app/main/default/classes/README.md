# Apex 도메인 폴더링 컨벤션

기능 도메인별 하위 폴더로 정리. SF CLI는 `classes/`, `triggers/` 안 nested 디렉토리를 자동 인식한다.
LWC는 컴포넌트 이름이 곧 폴더라 평탄 유지(`lwc/<name>/`).

## 도메인 매핑

| 폴더 | 클래스 | 도입 |
|---|---|---|
| `account/` | `AccountTriggerHandler`(+Test) | Day 1 |
| `lead/` | `LeadScoringService`, `CallMemoExtractService`, `LeadTriggerHandler`, `RfqInboundHandler`(+Tests) | Day 3 |
| `opp/` | `StageGateService`, `BusinessLicensePromptService` 등 | Day 4 (예정) |
| `quote/` | `PricingService`, `QuotePdfService`, `QuoteEmailService`, `QuoteRequoteService`, `EmailTrackingService` | Day 6 (예정) |
| `order/` | `DeliveryRiskCalculator`, `OrderScheduleSync` | Day 8 (예정) |
| `erp/` | `IExternalErpService`, `ErpServiceMock` | Day 8 (예정) |
| `ar/` | `PaymentService` | Day 9 (예정) |
| `cockpit/` | Cockpit 데이터 헬퍼 | Day 9 (예정) |

## 트리거도 동일 규칙

`triggers/<domain>/<ObjectName>Trigger.trigger`. 한 객체에 단일 트리거 + Handler 위임 패턴(D1 채택).

## 신규 추가 시

1. 도메인 결정 → 해당 폴더에 작성
2. 새 도메인이면 폴더 신설 + 본 README에 한 줄 추가
3. PermSet `classAccesses` 갱신
4. Test 100% 커버 + 회귀(전체 test) 통과 확인
