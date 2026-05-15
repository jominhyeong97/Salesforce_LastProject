# Opp 약속 납기일 + ERP 갭 시그널 설계 (D38)

**작성**: 2026-05-12 (Day 13 종료 후)
**상태**: Brainstorming 완료, Phase 1 구현 대기 (ERP Mock 갭 시그널은 Phase 2 보류)
**선행 의사결정**: D17(ERP Mock 일원화) · D23(StageGate 단순화) · D26(가격 안전) · D27(Order.Opportunity__c lookup)

## 0. 범위 분기 (2026-05-12 사용자 결정)

| Phase | 작업 | 본 세션 |
|---|---|---|
| **Phase 1** | Opp.Promised_Delivery_Date__c + Layout + StageGate 게이트 + Won→Order EndDate 복사 + 시드 | ✅ 진행 |
| Phase 2 | ErpServiceMock 갭 시그널 + Test 갱신 + 시연 §8 narrative 강화 | ⏸ 보류 (Mock 서버 작업과 함께 후속) |

---

## 1. 배경

현재 ERP Mock(`ErpServiceMock`)은 Order의 `PoNumber 끝자리 + Production_Status`만으로 riskScore(0~97)와 정적 signals를 반환한다. 시연 §8 동선은 동작하지만 두 가지 도메인 갭이 있다.

- **약속 납기일이 어디서도 명시적으로 확정되지 않음**. Lead RFQ는 `requestedDate`를 자유 텍스트로만 보관, Quote/Opp에 납기일 필드 부재, Order.EndDate는 시드 또는 트리거 default로 채워짐.
- **ERP 시그널이 "약속 대비 갭"을 말하지 않음**. "생산 라인 정체 — D-3 출고 지연 가능" 같은 정적 문구라 약속 vs 실제의 대비가 narrative 약함.

평가자 시각에서는 "ERP가 납기일을 생성한다"는 모델이 도메인적으로 잘못된 신호를 준다. 납기일은 영업 약속(Opp), ERP는 그 약속 대비 갭을 보고하는 역할이어야 책임 경계가 명확하다.

## 2. 결정 (D38)

**약속 납기일을 Opportunity의 속성으로 모델링한다.**

- Opp 신규 필드 `Promised_Delivery_Date__c` (Date)
- 견적 작성 단계 전환 게이트(D23)에 "납기일 not null" 조건 추가
- Won → Order 시 `Order.EndDate = Opp.Promised_Delivery_Date__c` 복사
- ErpServiceMock은 `Order.EndDate`를 읽어 "약속 대비 갭"을 결정론적으로 계산해 signals에 표시
- Quote/QuoteRequoteService/QuotePdf 전부 **무영향** — 납기일은 Opp 한 곳에서만 관리

## 3. 도메인 모델

```
Lead.requestedDate (자유 텍스트)
        ↓ Convert + AE 판단
Opp.Promised_Delivery_Date__c  ← Single Source of Truth (이 설계)
        ↓ Won
Order.EndDate                  ← 영업 약속 (Day 13 #2 D-N 배지 사용)
        ↓ ERP 동기화
ErpServiceMock signals         ← 약속 vs ERP 예상의 갭만 보고 (납기 생성 X)
```

평가자 답변: "납기일은 영업이 고객과 합의한 약속(Opp). ERP는 그 약속을 지킬 수 있는지 신호만 반환. 책임 경계 명확. 재견적·견적 버전과 독립."

## 4. 변경 범위

| 영역 | 파일 | 변경 |
|---|---|---|
| Opp 메타 | `objects/Opportunity/fields/Promised_Delivery_Date__c.field-meta.xml` | 신규 (Date, label=약속 납기일, required=false) |
| Opp Layout | `layouts/Opportunity-Opportunity (Sales) Layout.layout-meta.xml` 외 2종 | 약속 납기일 필드 추가 (Highlights 또는 Detail 섹션) |
| StageGate | `classes/opp/StageGateService.cls` | `checkQuoteReadiness`에 `Promised_Delivery_Date__c == null` 분기 1조건 추가 |
| StageGate Test | `classes/opp/StageGateServiceTest.cls` | 납기일 미입력 시 게이트 차단 케이스 1개 |
| Won→Order | `classes/opp/OpportunityTriggerHandler.cls` `handleAfterUpdate` | Order 인서트 시 `EndDate = opp.Promised_Delivery_Date__c` 매핑 |
| Won→Order Test | `classes/opp/OpportunityTriggerHandlerTest.cls` | EndDate 복사 검증 1케이스 |
| ERP Mock | `classes/order/ErpServiceMock.cls` | **Phase 2 보류** — SOQL에 `EndDate` 추가, signals에 갭 문구 |
| ERP Mock Test | `classes/order/ErpServiceMock_Test.cls` | **Phase 2 보류** |
| 시드 | `scripts/apex/seedData.apex` | 시연용 견적 단계 이상 Opp에 `Promised_Delivery_Date__c` 채움 (과거 Order는 EndDate 기존값 유지) |
| 권한 | `permissionsets/Sales_Cockpit_User.permissionset-meta.xml` | Opp 신규 필드 FLS Read/Edit |

Quote 메타 / quoteBuilder LWC / QuotePdf / QuoteTriggerHandler / QuoteRequoteService는 **전혀 손대지 않는다**.

## 5. StageGate 룰 (D23 확장)

- 현행 (D23): '발굴 → 견적 작성' = 사업자번호 1개
- 현행 (Day 13 #5): 첨부 검사 추가
- 신규 (D38): **'발굴 → 견적 작성' 전환 시 `Opp.Promised_Delivery_Date__c` not null 필수**

게이트 메시지(한국어): "납기일을 저장해주세요"

평가자 narrative: "납기일은 견적의 전제 조건. 견적 라인 가격이 납기에 좌우되므로 단계 게이트로 강제."

## 6. ErpServiceMock 갭 시그널 (Phase 2 — 본 세션 보류)

기존 점수 분포(D17-정정)와 jitter 결정론은 그대로 유지. signals 문구만 EndDate 대비 갭으로 강화:

| 분기 | 기존 signals | D38 갱신 signals |
|---|---|---|
| `PoNumber 끝 '6' + InProgress` (위험, 70~84) | 생산 라인 정체 — D-3 출고 지연 가능 / 고객 사전 통보 권고 | **ERP 예상 출고: {EndDate + (3 + jitter%3)일} — 약속 대비 D+{N} 지연 / 고객 사전 통보 권고** |
| `PoNumber 끝 '9' + InProgress` (대형지연, 85~97) | 대형 지연 — 60일 경과 / 즉시 고객 통보 + AE 직접 콜 필요 | **ERP 예상 출고: 미정 — 자재 미투입 / 즉시 고객 통보 + AE 직접 콜 필요** |
| 기타 InProgress (정상, 20~39) | 생산 진행 중 — 정상 경로 | **ERP 예상 출고: {EndDate}일 (정상 진행)** |
| Done (5~14) | 생산 완료 — 출고 대기 | (유지) |
| Shipped (0~7) | 출고 완료 | (유지) |
| Pending (25~39) | 생산 대기 — 자재 준비 중 | **ERP 예상 출고: {EndDate}일 — 자재 준비 중** |

**결정론 보장**: 지연 일수 = `3 + jitter(Order.Id, 3)` (3~5일). 같은 Order는 매 동기화마다 같은 갭. `Order.EndDate` null이면 갭 문구 생략하고 기존 정적 문구로 fallback.

## 7. 시연 narrative 강화

### §4 (Opp 발굴 → 견적 작성 게이트) — Phase 1
- AE가 Opp 들어감 → AI Insight 카드 확인
- Path '견적 작성' 클릭 → 게이트 ❌ "납기일을 저장해주세요"
- Opp 페이지에 납기일 직접 입력 (예: 6/15)
- 사업자번호 + 첨부 + 납기일 3-조건 통과 → '견적 작성' 전환 ✅

### §8 (ERP 동기화) — Phase 2 보류
- Phase 2에서 ErpServiceMock 갭 시그널 활성 시 narrative 강화 예정.

## 8. 회귀 영향

| 영역 | 위험 |
|---|---|
| Quote 메타/LWC/PDF | 0 (손대지 않음) |
| QuoteTriggerHandler (D37 자동 복사) | 0 (Promised_Delivery_Date 미참조) |
| QuoteRequoteService (재견적) | 0 (Quote 필드 무영향, Opp 참조) |
| Apex Test 332/332 | 신규 케이스 2~3개 추가, 기존 케이스 무영향 (signals 문자열 의존 1~2개만 갱신) |
| 시드 데이터 | 시연 Opp에 납기일 채움 — 게이트 통과 보장 |
| StageGate 기존 통과 Opp | 영향 없음 (게이트는 전환 시점만 검사) |

## 9. 테스트 계획

Phase 1
1. **StageGate 단위**: 납기일 미입력 시 `checkQuoteReadiness().passed == false` + 메시지 "납기일을 저장해주세요" 검증
2. **StageGate 단위**: 사업자번호 + 첨부 + 납기일 모두 충족 시 passed=true
3. **Won→Order 통합**: Opp.Promised_Delivery_Date__c = 6/15 → StageName='수주' update → Order 자동 생성 시 `Order.EndDate == Date(2026,6,15)` 검증
4. **Regression**: 전체 332개 케이스 재실행, 기존 케이스 무영향 확인

Phase 2 (보류)
- ErpServiceMock 단위: EndDate 갭 문자열·결정론·null fallback

## 10. 후속 — Phase 2 + Mock 서버 작업 (예고)

Phase 1 완료 후 진행:
1. **Phase 2 — ErpServiceMock 갭 시그널**: §6의 signals 강화 + Test 갱신
2. **Mock 서버 작업** (사용자 별도 진행): 실 Mock 서버(Beeceptor / MuleSoft / Site VFP 등)로 swap. `IExternalErpService` 인터페이스 유지하므로 D17 결정 그대로 — 구현체만 교체.

## 11. 비결정 사항

없음. Quote 미손대고 Opp 단일 필드로 모델링하는 방향으로 사용자 합의 완료.

## 12. 의사결정 번호

**D38** — 2026-05-12. 약속 납기일을 Opp의 속성으로 통합. ERP Mock은 갭만 보고. Quote/QuoteRequote 무영향. StageGate 게이트로 입력 강제.
