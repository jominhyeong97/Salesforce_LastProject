# 남은 일정 — 5/12 저녁 → 5/14 (목) 18:00 메일 제출

**작성**: 2026-05-12 (월) 오후 · **갱신**: 2026-05-13 (화) 오전 — 발표 취소·메일 제출 전환
**제출**: 2026-05-14 (목) **18:00 까지 메일** — 라이브 발표 없음. PPT/PDF 슬라이드 형태.
**잔여**: ~1.5일 (5/13 종일 + 5/14 오전~오후 6시 전)
**현재**: Day 1~9 완료 + Day 10 Phase A validate 통과, 전체 Apex Test ~210/210 PASS + 신규 18, Org-wide 80%
**Deliverable 변화 영향**:
- 라이브 발표 X → Q&A polish 라이브 답변 대신 **슬라이드에 자기설명 형태로 녹이기**
- 시연 라이브 X → **시연 동영상/스크린샷 캡처 필수** (슬라이드 임베드용)
- 1회성 메일 제출 → 슬라이드 안에 모든 narrative 포함되어야 함

---

## 1. PRD FR 완료 매트릭스 (P0/P1 기준)

### ✅ 완전 구현 (22건)

| FR | 구현 자산 |
|---|---|
| LEAD-001 3채널 인입 | phoneLeadIntake/visitLeadIntake/RfqInboundHandler |
| LEAD-003 Lead Scoring | LeadScoringService |
| LEAD-004 Lead Convert 자동 매핑 | LeadTriggerHandler (D20 Apex) |
| LEAD-005 Lead 우선순위 콕피트 | aeCockpit.priorityLeads 섹션 |
| OPP-001 Stage 정의 | StandardValueSet 한국어 6단계 |
| OPP-004 사업자등록증 OCR | BusinessLicensePromptService + businessLicenseUpload |
| STAGE-001/002 게이트 + 차단 | stageGateChecklist + OpportunityTriggerHandler.handleBeforeUpdate |
| QUOTE-002 Quote Builder 인라인 | quoteBuilder + quoteLineEditor |
| QUOTE-003 할인 금액→% 자동 | Discount_Percent__c Formula |
| QUOTE-004 Quote PDF | QuotePdfService (한국식 Aqua, NanumGothic) |
| QUOTE-005 Quote 이메일 발송 | QuoteEmailService |
| QUOTE-006 이메일 추적 | EmailTrackingService (@RestResource) — **Site 미배포** |
| QUOTE-007 응답 의도 분류 | EmailIntentClassifyService (IntentClassify Prompt) |
| QUOTE-009 재견적 자동 초안 | QuoteRequoteService (RequoteDraft Prompt) |
| ORDER-001 Won 후 Order 자동 | OpportunityTriggerHandler.handleAfterUpdate (Day 9 #1) |
| ORDER-002 ERP 동기화 | ErpServiceMock + OrderErpSyncService + orderRiskCard (LWC 버튼) |
| ORDER-003 납기 위험 점수 | ErpServiceMock (DeliveryRiskCalculator 역할) |
| ORDER-006 출고 완료 등록 | ShippingCompleteService + shippingComplete LWC |
| AR-001 분할 입금 추적 | PaymentService + paymentRegister LWC |
| AR-002 장기미수금 자동 분류 | LongTermDebtorScheduler (Schedulable) |
| COCKPIT-001/002 콕피트 5카드 | aeCockpit (Home Page 배치 완료) |
| LOC-001~004 한국 정서 | Picklist 한국어 + AccountTriggerHandler 사업자번호 체크섬 |

### ⚠️ 부분 구현 (D25 폐기 또는 narrative 우회)

| FR | 현재 상태 | 조치 필요 |
|---|---|---|
| LEAD-002 RFQ 사양 자동 추출 (SpecExtract Prompt) | RfqInboundHandler 내 정규식 (Prompt Builder 미사용) | narrative — D25(폐기 안 함) 답변 또는 1h 교체 |
| LEAD-006 PHONE 통화메모 추출 | CallMemoExtractService 정규식 mock | **★ 진짜 AI 교체 1~1.5h** |
| OPP-002 Stage 자동 전이 | Won 후 Order 자동 ✅, Quote 발송→Quote Sent 자동 ❌ | 30분 (Quote Trigger 또는 Flow) |
| OPP-003 Stage별 권장 액션 | oppInsightCard.nextActions 로 부분 | narrative 우회 가능 |
| ORDER-002 Scheduled Cron | LWC 버튼만 작동, 매일 03:00 미등록 | 5분 (Anonymous Apex 한 줄) |
| ORDER-003 DeliveryRiskCalculator 별도 | ErpServiceMock 내부 | narrative — "동일 책임 한 클래스로 통합" |
| ORDER-004 사전 통보 메일 (Prompt `DelayNotice`) | orderRiskCard.mailto 로 대체 | narrative 가능 또는 1h Prompt 추가 |
| AR-002 Schedulable 실 등록 | 코드 있음, System.schedule 실행 안 됨 | 5분 (Anonymous Apex 한 줄) |
| AR-003 Quote Builder 헤더 AR 정보 (P1) | longTermDebtorBanner 있음, Quote 헤더 미표시 | 30분 |
| QUOTE-006 Site 픽셀 추적 | Custom Label __UNSET__, Site 미배포 | 1~2h Setup |

### ❌ 미구현 — P0 핵심

| FR | 영향 | 시간 |
|---|---|---|
| **QUOTE-001 AI Quote 초안** | **D25로 폐기·대체 (oppInsightCard)** — 정식 폐기 결정 | 0 (narrative) |
| **QUOTE-008 7일 무응답 follow-up** | P1 마크지만 시연 §6 부속 | 1h Schedulable |
| **AGENT-001 Agentforce 5 Action** | **★★★ 시연 §10 핵심. 5종 기술 중 통째로 없음** | 3~4h |
| **COCKPIT-003 Agentforce 입력창** | agentforceInputBar LWC | AGENT-001 와 함께 1h |
| ORDER-005 orderScheduleTracker (P1) | 분할 납품 간트 | 시드로 우회 |

### NFR 부족
| NFR | 현재 | 목표 | 비고 |
|---|---|---|---|
| TEST-001 Apex 커버리지 | 80% | ≥85% | 5%p 보강 |
| TEST-003 LWC Jest | 0건 | 핵심 LWC | P2 — 시간 없으면 skip |
| TEST-002 핵심 클래스 ≥90% | StageGate 52% / QuotePdfController 17% / EmailIntentClassifyService 67% | ≥90% | 약점 보강 |

---

## 2. 우선순위 라벨

| 라벨 | 의미 |
|---|---|
| ★★★ | 시연 골든패스 멈춤 위험, 평가자 핵심 의심 회피 |
| ★★ | 시연 매끄러움 + 평가 임팩트 |
| ★ | 정량 평가 가점, 발표 후 v2 가능 |

---

## 3. 일정 — 5/12 저녁 → 5/14 오전

### 🕕 5/12 (월) 저녁 — Day 9 사후 안정화 (2h)

| 시간 | 작업 | 우선도 |
|---|---|---|
| 30분 | **C 골든패스 1차 리허설** — 시연 §1~§10 직접 따라가며 끊김 지점 식별 | ★★★ |
| 90분 | 발견된 버그 즉시 fix + 시드 데이터 정합 점검 | ★★★ |
| 10분 | `System.schedule('LongTermDebtorDaily', ...)` 등록 (Anonymous Apex 한 줄) | ★★ |

### 🌅 5/13 (화) 오전 — Agentforce (4h)

| 시간 | 작업 |
|---|---|
| 30분 | Agentforce Topic `SalesCockpitAssistant` 생성 (Setup → Agentforce Builder) |
| 2h | 5 Action 구현 — getTodayPriorityList / getOrderAtRisk / getAccountSummary / draftFollowupEmail / getCrossSellCandidates (Invocable Apex + Action Schema) |
| 1h | `agentforceInputBar` LWC — 콕피트 상단 자연어 입력 (Messaging Component 또는 inline) |
| 30분 | E2E 검증 — Agentforce에서 자연어 질의 → 5 Action 호출 확인 |

### 🌇 5/13 (화) 오후 — 보완 작업 (4h)

| 시간 | 작업 | 우선도 |
|---|---|---|
| 1~1.5h | **B CallMemoExtract — 정규식 → 진짜 AI 교체** (OppInsight 패턴 차용, stripCodeFences D26) | ★★ |
| 30분 | OPP-002 Quote 발송→Quote Sent Stage 자동 전이 | ★ |
| 30분 | AR-003 Quote Builder 헤더 AR 정보 표시 | ★ |
| 1h | QUOTE-008 7일 무응답 Schedulable + Task 자동 | ★ |
| 30분 | TEST 커버리지 80→85%+ (약점 클래스 보강 — StageGate/QuotePdfController/EmailIntentClassifyService) | ★ |

### 🌙 5/13 (화) 저녁 — 시연 리허설 (2h)

| 시간 | 작업 |
|---|---|
| 1h | **C 골든패스 2차 리허설** — 6분 타임 체크, 발표자 시점 |
| 1h | **D Q&A 시뮬레이션** — D17/18/25/26/27 답변 polish + 예상 질문 정리 |

### 🌅 5/14 (목) 오전~오후 — 슬라이드 작성 + **18:00 메일 제출** (8h)

| 시간 | 작업 |
|---|---|
| 09:00~10:00 | 시연 환경 점검 + 시연 데이터 ID 메모 (Lead 1 / Opp 1 / Quote 1 / Order 1 / Account 1) |
| 10:00~13:00 | **시연 동영상/스크린샷 캡처** — 골든패스 §1~§10 각 단계. OBS 또는 PowerPoint 화면 녹화 |
| 13:00~17:30 | **슬라이드 작성** (PPT 또는 PDF) — HANDOFF §6 Phase B.7 슬라이드 구성안 참조. 9 섹션. |
| 17:30~17:55 | 최종 검토 — 오타·정합성·동영상 재생 확인 |
| **18:00** | **메일 발송 (마감)** |

---

## 4. 의사결정 보류 (시간 부족 시 narrative 우회)

| 항목 | narrative 답변 |
|---|---|
| QUOTE-001 AI Quote 초안 폐기 | "D25로 Opp Insight 대체. AI는 자동 생성보다 분석·요약이 임팩트 큼" |
| LEAD-002 SpecExtract 정규식 | "Day 5 OCR 패턴 동일, 시연 §2 메모 추출이 AI 임팩트 대표" |
| LEAD-006 통화메모 정규식 | (B 작업 안 할 시) "Prompt Builder는 5종 기술 시연 + OCR + 의도 분류 + 재견적 3곳에 집중. 통화메모는 양식이 결정적이라 정규식 충분" |
| ORDER-004 DelayNotice Prompt | "사전 통보 메일은 mailto 로 즉시 발송. Prompt Builder는 가격·계약 분석에 집중" |
| ORDER-005 orderScheduleTracker P1 | "P1 — 시드 데이터로 시각화 충분, 분할 납품 패턴은 후속" |
| QUOTE-006 Site 픽셀 추적 | "코드는 완성 (EmailTrackingService @RestResource). Site 활성화는 IT/보안 검토 후, 본 발표는 백엔드 흐름 시연" |

---

## 5. 최소 실행 가능 path (시간 부족 시)

**5/14 18:00 메일 제출 마감용 최소 작업**:

1. ★★★ Agentforce 5 Action 실 deploy + 메타 + 활성화 (5/13 오전 3~4h)
2. ★★★ 시연 동영상/스크린샷 캡처 (5/14 오전 3h)
3. ★★★ 슬라이드 작성 PPT/PDF (5/14 오후 4h, 9 섹션)
4. ★★ Agentforce 자연어 질의 E2E (5/13 저녁 30분, 슬라이드 임베드용)

**총 ~11시간** — 시간 빠듯. 골든패스가 안 깨지면 narrative 채울 시간 여유.

---

## 6. 제출 D-Day 체크리스트 (5/14 18:00 마감)

- [ ] `sf org display --target-org My_Org` — 연결 확인
- [ ] Apex Test 전체 PASS 확인 + 커버리지 캡처(슬라이드용)
- [ ] 시연 데이터 ID 메모 (Lead 1, Opp 1, Quote 1, Order 1, Account 1)
- [ ] **시연 동영상 임포트 확인** (슬라이드 재생 테스트)
- [ ] 슬라이드 9 섹션 정합성 — 골든패스/AI 라인/ERP 게이트웨이/Agentforce/의사결정/카탈로그/한계 모두 포함
- [ ] **메일 수신처·제목·첨부 확인** 후 발송 (17:55 까지)
