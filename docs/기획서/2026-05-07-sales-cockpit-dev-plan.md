# Sales Cockpit 개발 계획서

**v0.3** | 2026-05-07 | 발표 2026-05-14 오후
**기반**: `2026-05-07-sales-cockpit-prd.md` **v0.7**
**Org**: My_Org (Agentforce DE)

> v0.3: ERP Beeceptor 제거 → Apex Mock 일원화. NC 0, 외부 callout 0. 시연 즉석 동기화 버튼 추가 (Day 8). NG-017 (Contract) 반영.
> v0.2 변경: OCR을 Prompt Builder 멀티모달로 전환, CompanyInfo 제거(NG-016), Beeceptor 4→2 path, NC 4→2, Prompt Template 6→7, P0 34→33.

---

## 1. 개요

- **목표**: PRD v0.6의 P0 33개 + 시연 골든패스 10단계 무결 시연
- **가용 일자**: 2026-05-07(수) ~ 2026-05-14(수 오전) = **8일**
- **단계**: Day 1 ~ Day 10 (일부는 같은 날에 묶음, §6 캘린더 매핑 참조)
- **페르소나**: AE 김민수, 한도정밀 가상 회사
- **차별화 4가지**: L2C 통합·AI HITL·ERP 게이트웨이·미수금 시각

---

## 2. 기술 스택

| 영역 | 도구·기술 |
|---|---|
| 플랫폼 | Salesforce Sales Cloud + Agentforce + Prompt Builder |
| UI | LWC (JS + HTML + CSS, SLDS 토큰) |
| 비즈니스 로직 | Apex (Service Class + Trigger + Invocable) |
| 자동화 | Flow (Record-triggered, Scheduled, Screen) |
| AI | Prompt Builder Templates 7종, Agentforce Topic + Actions |
| 외부 통신 | 0 (ERP는 Apex Mock 클래스, OCR은 Prompt Builder 내부) |
| 도구 | VS Code + Salesforce Extensions, sf CLI v2, Git |

---

## 3. 환경 사전 설정 체크리스트 (Day 1 시작 전)

- [ ] Org "My_Org" 연결 확인 (`sf org display`)
- [ ] Org Locale → ko_KR
- [ ] Org Default Currency → KRW
- [ ] Sales Cloud 라이선스 확인
- [ ] Agentforce / Prompt Builder 활성화 확인
- [ ] sfdx-project.json 점검
- [ ] Permission Set `Sales_Cockpit_User` (빈 껍데기) 작성
- [ ] AE 사용자 + 매니저 사용자 1명씩 (가상)

---

## 4. Day별 체크리스트

### Day 1 — 데이터 모델 & 환경

**산출물**
- [ ] 커스텀 객체 `Payment__c` (필수 필드 5개)
- [ ] 표준 객체 커스텀 필드 26개 배포 (Account 6, Lead 3, Quote 5, QuoteLineItem 2, Order 6, Contact 2, EmailMessage 1)
- [ ] Picklist 값 (Source_Channel__c, Korean_Title__c, Korean_Department__c, Production_Status__c, EmailMessage.Intent__c)
- [ ] Apex Trigger `AccountTrigger` — Business_Number__c 체크섬 검증
- [ ] Permission Set `Sales_Cockpit_User` 필드 권한 부여

**검증**
- [ ] `sf project deploy start` 성공
- [ ] 모든 필드가 Object Manager에서 보임
- [ ] 사업자번호 포맷 위반 시 에러 메시지

**FR 매핑**: DR-OBJ-001, DR-FLD-001~026, FR-LOC-004
**의존성**: 없음 (출발점)

---

### Day 2 — 시드 데이터

**산출물**
- [ ] `scripts/apex/seedData.apex` — Account 30 + Contact 60 + Product 50 + 과거 Order 100 + Payment(분할/장기미수 시나리오 포함). Order는 OrderNumber 끝자리에 위험 카테고리 분포 셋팅 (위험 5건/대형지연 5건/정시 90건). Delivery_Risk_Score__c·Last_ErpSync_At__c는 null로 초기화 (시연 시 동기화 버튼으로 갱신).
- [ ] `scripts/apex/seedKoreanData.apex` — 한국 가상 회사명·사업자번호·이름·직급
- [ ] 사업자등록증 샘플 PDF/이미지 5건 (`docs/samples/`)

**검증**
- [ ] 시드 스크립트 실행 후 카운트 일치
- [ ] Order 100건의 끝자리 분포 확인 (위험 5/대형지연 5/정시 90)
- [ ] Delivery_Risk_Score__c·Last_ErpSync_At__c는 시드 직후 null

**FR 매핑**: DR-DATA-001~006
**의존성**: Day 1

---

### Day 3 — Lead 인입 (3채널 + 통화메모 추출)

**산출물**
- [ ] LWC `phoneLeadIntake` (전화 Lead 등록 모달)
  - 메모 textarea + "메모로 자동 채우기" 버튼
  - 폼 필드: 회사명·담당자·연락처·부품·수량·납기
- [ ] LWC `visitLeadIntake` (방문 Lead 등록 모달)
- [ ] Email Service `RfqInbound` 클래스 — rfq@hando.example 이메일 → Lead 자동 생성
- [ ] Prompt Builder Template `SpecExtract` (메일·첨부 → 사양 JSON)
- [ ] Prompt Builder Template `CallMemoExtract` (자유 메모 → 폼 필드 JSON)
- [ ] Apex `LeadScoringService.cls` (가중치 산식 + 비동기 호출 가능)
- [ ] Flow `Lead_Convert_Auto_Mapping` (Convert 시 Account/Contact/Opp 자동)

**검증**
- [ ] EMAIL 채널: 메일 발송 → 60초 이내 Lead 생성 + RFQ_Spec_JSON__c 채워짐
- [ ] PHONE 채널: 메모 입력 → 자동 채우기 → 폼 필드 노란 점 표시
- [ ] Convert 시 Account 중복 검출 동작
- [ ] Lead Score 0~100 범위

**FR 매핑**: FR-LEAD-001/002/004/005/006
**의존성**: Day 1, Day 2

---

### Day 4 — Apex 서비스 계층 (외부 통합 0)

**산출물**
- [ ] Apex Interface `IExternalErpService` (getProductionSchedule, postShippingDone) — 인터페이스만 정의 (실 구현 후속 릴리스)
- [ ] Apex `ErpServiceMock.cls` (단독 구현, 외부 callout 없음)
  - orderId 끝자리 분기로 위험 카테고리 결정적 (0~5 정시 / 6~8 위험 / 9 대형지연)
  - 날짜는 today 기준 상대값 계산
  - postShippingDone는 no-op (SF 내부 처리만)
- [ ] HttpCalloutMock 테스트 클래스 0개 (callout 없음)
- [ ] ErpServiceMockTest.cls — 분기 로직 단위 테스트 (≥90% coverage)

**검증**
- [ ] ErpServiceMock 단위 테스트 통과 (분기 케이스 3개)
- [ ] 외부 callout 시도 0건 (전체 force-app에 Http.send 호출 없음 검증)

**FR 매핑**: **FR-ORDER-002, NFR-PERF-003/004**
**의존성**: Day 1 (필드)

---

### Day 5 — Opp + 사업자등록증 OCR + Stage Gate

**산출물**
- [ ] Apex `BusinessLicensePromptService.cls` — Prompt Builder Template `BusinessLicenseExtract` invoke (이미지 base64 → JSON)
- [ ] Prompt Builder Template `BusinessLicenseExtract` (멀티모달 입력 — ContentDocument/ContentVersion 이미지 → JSON 출력)
- [ ] LWC `businessLicenseUpload` (드래그&드롭 + OCR 호출 + 라인별 편집)
- [ ] LWC `stageGateChecklist` (5개 객체별 게이트 룰)
- [ ] Apex `StageGateService.cls` (게이트 평가 + 다음 단계 가능 여부 반환)
- [ ] Flow `Opportunity_Stage_Auto_Transition`
- [ ] Opp/Account Lightning Page에 LWC 임베드

**검증**
- [ ] 사업자등록증 PDF 업로드 → 5초 이내 라인별 결과 표시
- [ ] AE 확인 → Account 자동 채움
- [ ] 게이트 ❌ 시 다음 단계 버튼 비활성화 + 툴팁
- [ ] ❌ 클릭 시 입력 필드로 페이지 스크롤

**FR 매핑**: FR-OPP-001~004, FR-STAGE-001/002, UI-OCR, UI-STAGE-GATE
**의존성**: Day 4 (외부 통합)

---

### Day 6 — Quote Builder (AI 초안 + 할인 + PDF)

**산출물**
- [ ] LWC `quoteBuilder` (좌측 라인 편집 + 우측 PDF 미리보기)
- [ ] LWC `quoteLineEditor` (라인 단위 컴포넌트, 인라인 편집)
- [ ] Prompt Builder Template `SkuMatch` (사양 → 카탈로그 매칭, top 3)
- [ ] Apex `PricingService.cls` (단가·할인 금액·할인율 자동 계산)
- [ ] Apex `QuotePdfService.cls` (PDF 생성 — VisualForce 또는 PDF 라이브러리)
- [ ] Formula 필드 `QuoteLineItem.Discount_Percent__c` (할인 금액 / (단가×수량))

**검증**
- [ ] AI 초안 5초 이내 표시
- [ ] 라인별 SKU/수량/단가/할인 인라인 편집 동작
- [ ] 할인 40,000 → "1.36% 할인" 자동 표시
- [ ] PDF 3초 이내 생성, ContentVersion 첨부
- [ ] 할인율 ≥20% 노랑, ≥30% 빨강

**FR 매핑**: FR-QUOTE-001/002/003/004, NFR-PERF-001/005
**의존성**: Day 1 (필드), Day 5 (Opp)

---

### Day 7 — Quote 추적 + 의도 분류 + 재견적 자동 초안

**산출물**
- [ ] Apex `EmailTrackingService.cls` + Apex REST `/services/apexrest/track/*`
- [ ] Apex `QuoteEmailService.cls` (PDF 첨부 + 추적 픽셀·링크 + 한국어 템플릿)
- [ ] Email Service `QuoteResponseInbound` 클래스
- [ ] Prompt Builder Template `IntentClassify` (응답 메일 → 6 카테고리)
- [ ] Prompt Builder Template `RequoteDraft` (응답 + 기존 Quote → 변경된 라인)
- [ ] Apex `QuoteRequoteService.cls` (Quote 복제 + 라인 변경 적용)
- [ ] Flow `Quote_NoResponse_7Day` (Scheduled Path)

**검증**
- [ ] Quote 발송 후 추적 픽셀 호출 → Last_Opened_At__c 갱신
- [ ] 응답 메일 → Intent__c 자동 분류 (6 카테고리)
- [ ] "재견적" 분류 → 새 Quote (Status='Draft') 자동 생성
- [ ] 7일 무응답 → AE Task 생성

**FR 매핑**: FR-QUOTE-005/006/007/008/009, NFR-AUDIT-001
**의존성**: Day 6

---

### Day 8 — Order + 납기 위험 + 출고 등록

**산출물**
- [ ] Flow `Opportunity_Won_To_Order` (Won 시 Order + OrderItem 자동 생성)
- [ ] Apex `DeliveryRiskCalculator.cls` (위험 점수 산식)
- [ ] Scheduled Apex `OrderScheduleSync.cls` **(매일 03:00 KST + LWC 수동 버튼 공유)**
- [ ] Prompt Builder Template `DelayNotice` (사전 통보 메일 초안)
- [ ] LWC `orderScheduleTracker` (분할 납품 간트/타임라인)
- [ ] LWC `shippingComplete` (출고 완료 등록 모달)
- [ ] Order Lightning Page에 임베드
- [ ] Order에 `Last_ErpSync_At__c` DateTime 필드 추가 + Permission Set 갱신 (Sales_Cockpit_User)
- [ ] LWC `orderRiskCard` 상단에 "🔄 ERP 동기화" 버튼 + 마지막 동기화 시각 표시
- [ ] Apex Invocable `OrderScheduleSync.runOnce(orderIds)` — LWC 수동 버튼·Scheduled Cron 공유
- [ ] LWC 클릭 시 ErpServiceMock 호출 → Order.Delivery_Risk_Score__c·Last_ErpSync_At__c·Production_Status__c·Production_Start/End_Date 갱신

**검증**
- [ ] Stage='Won' 전이 → Order 자동 생성, OrderItem 1:1 매핑
- [ ] Scheduled Apex 03:00 동작 + Production_Start/End_Date 갱신
- [ ] 위험 점수 ≥70 → AE Task + DelayNotice 메일 초안
- [ ] 출고 완료 등록 → Production_Status='Shipped' + Shipped_Date 저장
- [ ] "🔄 ERP 동기화" 버튼 클릭 → ErpServiceMock 호출 → Last_ErpSync_At__c 갱신 확인

**FR 매핑**: FR-ORDER-001~006
**의존성**: Day 4 (ERP Service), Day 7 (Won 트리거)

---

### Day 9 — AR (분할 입금 + 장기미수) + 콕피트

**산출물**
- [ ] LWC `paymentRegister` (입금 등록 모달)
- [ ] Apex `PaymentService.cls` (Payment 생성 + Order Outstanding_Amount 갱신)
- [ ] Formula 필드 `Order.Outstanding_Amount__c` = Total_Amount − Σ Paid_Amount
- [ ] Scheduled Flow `AR_Long_Term_Debtor_Daily` (매일 03:00, 180일+ 자동 분류)
- [ ] LWC `aeCockpit` (Lightning App Page Home)
- [ ] LWC 카드 5개: `rfqCard`, `quoteTrackingCard`, `orderRiskCard`, `arActionCard`, `leadPriorityCard`
- [ ] Account Lightning Page 빨간 띠 LWC `longTermDebtorBanner`
- [ ] Account 목록 뷰 빨간 행 (List View Conditional Formatting)

**검증**
- [ ] 입금 등록 → Order에 누적 입금액·잔액 표시
- [ ] 누적 ≥ Total_Amount → "입금완료" 라벨
- [ ] 장기미수금 Account → 페이지 상단 빨간 띠 + 카드 빨간 배경
- [ ] 콕피트 5카드 2초 이내 로딩

**FR 매핑**: FR-AR-001/002/003, FR-COCKPIT-001/002/003, UI-AR-001~005, NFR-PERF-002
**의존성**: Day 8 (Order)

---

### Day 10 — Agentforce + Localization + 리허설

**산출물**
- [ ] Agentforce Topic `SalesCockpitAssistant`
- [ ] 5 Action: getTodayPriorityList, getOrderAtRisk, getAccountSummary, draftFollowupEmail, getCrossSellCandidates(T2)
- [ ] 각 Action 매핑된 Apex Invocable Method
- [ ] LWC `agentforceInputBar` (콕피트 상단)
- [ ] 페이지 레이아웃 한국어 라벨 일괄 점검 (Translation Workbench 또는 Custom Label)
- [ ] Email Template 한국어 (Quote 발송, follow-up, DelayNotice, 사전통보)
- [ ] 골든패스 10단계 리허설 (E2E)
- [ ] 발표 자료(Keynote/PPT) 골격

**검증**
- [ ] Agentforce 자연어 질의 5초 이내 응답
- [ ] 모든 화면 한국어
- [ ] 골든패스 10단계 무결 시연
- [ ] Apex 커버리지 ≥85% (`sf apex run test`)

**FR 매핑**: FR-AGENT-001/002, FR-LOC-001~004, NFR-LOC, NFR-TEST
**의존성**: Day 1 ~ Day 9 (전체)

---

## 5. 의존성 그래프

```
Day 1 (데이터 모델)
   ├─→ Day 2 (시드 데이터)
   │      ├─→ Day 3 (Lead 인입)
   │      └─→ Day 4 (Apex 외부 통합)
   │              └─→ Day 5 (Opp + OCR + Gate)
   │                      └─→ Day 6 (Quote Builder)
   │                              └─→ Day 7 (추적 + 의도 + 재견적)
   │                                      └─→ Day 8 (Order + 납기)
   │                                              └─→ Day 9 (AR + 콕피트)
   │                                                      └─→ Day 10 (Agentforce + 리허설)
```

**Critical Path**: Day 1 → 2 → 4 → 5 → 6 → 7 → 8 → 9 → 10
**병행 가능**: Day 3(Lead 인입)는 Day 4와 병행 가능. Day 5는 Day 4 일부만 완성되면 시작 가능.

---

## 6. 캘린더 매핑 (8일에 10단계 압축)

| 캘린더 | 요일 | Day | 작업 | 비고 |
|---|---|---|---|---|
| 5/7 | 수 | **Day 1** | 데이터 모델 | 오늘 |
| 5/8 | 목 | **Day 2 + 3** | 시드 데이터 + Lead 인입 | 병행 |
| 5/9 | 금 | **Day 4 + 5** | Apex 외부 통합 + Opp/OCR/Gate | 병행 |
| 5/10 | 토 | **Day 6** | Quote Builder | 집중 |
| 5/11 | 일 | **Day 7** | 추적·의도·재견적 | 집중 |
| 5/12 | 월 | **Day 8** | Order + 납기 | |
| 5/13 | 화 | **Day 9** | AR + 콕피트 | |
| 5/14 | 수 오전 | **Day 10** | Agentforce + 리허설 | 발표 직전 |

→ 주말 2일 활용 필수. Day 6·7이 가장 부하 큰 구간.

---

## 7. 산출물 카탈로그

### 7.1 LWC (총 14개)

| 컴포넌트 | 역할 |
|---|---|
| `aeCockpit` | Home 컨테이너 |
| `rfqCard` | 미컨버전 Lead 카드 |
| `quoteTrackingCard` | 응답 없는 Quote 카드 |
| `orderRiskCard` | 위험 Order 카드 |
| `arActionCard` | 입금 임박/연체 + 미수금 Account |
| `leadPriorityCard` | 우선순위 Lead |
| `phoneLeadIntake` | 전화 Lead 등록 + 통화메모 추출 |
| `visitLeadIntake` | 방문 Lead 등록 |
| `businessLicenseUpload` | 사업자등록증 OCR (Opp/Account) |
| `stageGateChecklist` | 단계 전이 게이트 |
| `quoteBuilder` + `quoteLineEditor` | AI 초안 + 인라인 편집 |
| `orderScheduleTracker` | 분할 납품 간트 |
| `shippingComplete` | 출고 완료 등록 |
| `paymentRegister` | 입금 등록 |
| `longTermDebtorBanner` | Account 페이지 빨간 띠 |
| `agentforceInputBar` | 콕피트 상단 자연어 입력 |

### 7.2 Apex 클래스 (총 12개)

| 클래스 | 역할 |
|---|---|
| `LeadScoringService` | Lead Score 계산 |
| `BusinessLicensePromptService` | Prompt Builder OCR invoke (이미지→JSON) |
| `IExternalErpService` (인터페이스) | ERP 추상화 |
| `ErpServiceMock` | 단독 구현 (외부 callout 없음, orderId 끝자리 분기) |
| `PricingService` | 단가/할인/AR 계산 |
| `QuotePdfService` | PDF 생성 |
| `QuoteEmailService` | 이메일 발송 + 추적 |
| `QuoteRequoteService` | Quote 복제 + 변경 적용 |
| `EmailTrackingService` + REST | 픽셀/링크 핸들러 |
| `DeliveryRiskCalculator` | 위험 점수 |
| `OrderScheduleSync` (Scheduled) | 매일 03:00 ERP 동기화 |
| `PaymentService` | 입금 등록 |
| `StageGateService` | 게이트 평가 |
| `AccountTrigger` | 사업자번호 검증 |

### 7.3 Flow

| Flow | 타입 |
|---|---|
| `Lead_Convert_Auto_Mapping` | Auto-launched |
| `Opportunity_Stage_Auto_Transition` | Record-Triggered |
| `Opportunity_Won_To_Order` | Record-Triggered |
| `Quote_NoResponse_7Day` | Scheduled Path |
| `AR_Long_Term_Debtor_Daily` | Schedule-Triggered |

### 7.4 Prompt Builder Template (7개)

| Template | 입력 → 출력 |
|---|---|
| `BusinessLicenseExtract` | 사업자등록증 이미지 → 사업자번호·회사명·대표자·주소·업종 JSON |
| `SpecExtract` | 메일+첨부 텍스트 → 사양 JSON |
| `CallMemoExtract` | 자유 메모 → 폼 필드 JSON |
| `SkuMatch` | 사양 → 카탈로그 SKU top 3 |
| `IntentClassify` | 응답 메일 → 6 카테고리 |
| `RequoteDraft` | 응답+기존 Quote → 변경된 라인 |
| `DelayNotice` | Order 정보 → 사전 통보 메일 |

### 7.5 Agentforce Action (5개)
PRD §FR-AGENT-001 참조. 각 Action에 매핑되는 Apex Invocable.

---

## 8. 테스트 전략

### 8.1 Apex Test
- 핵심 Service 클래스별 ≥90% (PricingService, LeadScoringService, QuoteRequoteService 등)
- HttpCalloutMock으로 외부 API 모두 mock
- Org-wide ≥85%

### 8.2 LWC Jest
- `quoteBuilder` 라인 편집 + 할인 % 자동 계산
- `phoneLeadIntake` 메모 추출 후 폼 자동 채움
- `stageGateChecklist` 게이트 평가

### 8.3 통합 테스트 (수동)
- 골든패스 10단계 E2E (시연 시나리오와 동일)

### 8.4 Flow 테스트
- 분기마다 시나리오 1개씩 (Lead Convert 중복/신규, Won→Order, Scheduled 호출)

---

## 9. 시연 리허설 시나리오 (10단계 / 6분)

| # | 시간(누적) | 액션 | 보이는 것 |
|---|---|---|---|
| 1 | 0:00 | 콕피트 열기 | 5카드 표시 |
| 2 | 0:30 | "전화 Lead 등록" → 메모 입력("LG디스플레이 박 과장 010-1234-5678 베어링 6204 100개 5월말") → "메모로 자동 채우기" | 폼 자동 채움 (노란 점) |
| 3 | 1:00 | 게이트 ✅ → Lead Convert | Account/Contact/Opp 자동 생성 |
| 4 | 1:45 | Opp Discovery → Quote 게이트 ❌ → 사업자등록증 PDF 업로드 → OCR 자동 채움 → 게이트 ✅ | Account 보강 + 회사정보 추가 |
| 5 | 2:45 | "AI 견적 초안" → 라인 자동 + 할인 40,000 입력 → 1.36% 자동 | Quote Builder |
| 6 | 3:30 | 발송 (한도 정보 표시만) | 메일 발송 + Stage='Quote Sent' |
| 7 | 4:00 | 응답 메일 시뮬 → "재견적" 분류 → 자동 초안 생성 → AE 검토 → 재발송 → "수락" → Won → Order 자동 | Stage 전이 시각화 |
| 8 | 4:45 | 콕피트 Order Risk Card → 위험 78점 → DelayNotice 메일 초안 → 발송 | 사전 통보 |
| 9 | 5:15 | "출고 완료 등록" → 분할 입금 등록 3회 (50/30/20%) | 잔액 추적 |
| 10 | 5:45 | 다른 거래처 장기미수금 빨간 띠 → Agentforce에 "장기미수 거래처" 자연어 질의 | 자연어 응답 |

---

## 10. 리스크 및 완화

| 리스크 | 완화 |
|---|---|
| 8일에 P0 33개 부담 | Day별 산출물 명확, Tier 2 stretch는 시간 남으면만 |
| Prompt Builder 출력 품질 불안정 | Few-shot 예시 5개 이상, 신뢰도 < 0.6 시 수동 입력 fallback |
| LWC 컴포넌트 비대화 | 카드 단위 분리 (이미 14개로 쪼갬) |
| Approval Process·Flow 충돌 | 결재 제거됨(NG-009), 이슈 없음 |
| ko_KR Locale로 인한 표준 라벨 깨짐 | Custom Label 사용, 표준 필드 라벨 변경은 페이지 레이아웃에서 |
| Email Service 인입 메일 디버깅 어려움 | 시연용 가짜 메일은 Apex 스크립트로 주입 가능 |
| Sales Cloud 색깔 의심 | NG-009~015로 ERP/회계 영역 명시적 제외, 평가 답변 미리 준비 |

---

## 11. 발표 준비 체크리스트 (Day 10 후반)

- [ ] 발표 슬라이드 (페르소나·문제·해결·차별화·시연·아키텍처)
- [ ] 시연 영상 백업 (네트워크 문제 대비)
- [ ] 시드 데이터 다시 적재 (시연 직전 초기화)
- [ ] 질의응답 예상 5종 답변 준비
  - "왜 영업 시스템이 ERP 영역까지?" → 게이트웨이 패턴 답변
  - "왜 AI를 굳이?" → 자유 텍스트 영역만 한정 답변
  - "한국 정서 적용한 이유?" → UX·페르소나 충실도 답변
  - "결재가 없는데 괜찮은가?" → NG-009 답변
  - "세금계산서 빠진 이유?" → NG-014 답변

---

## 12. 매일의 일과 패턴 (권장)

| 시간 | 활동 |
|---|---|
| 09:00~10:00 | 어제 산출물 검증 + 오늘 Day 작업 시작 |
| 10:00~12:00 | 핵심 산출물 1-2개 |
| 13:00~17:00 | 핵심 산출물 나머지 + 검증 |
| 17:00~18:00 | sf project deploy + 테스트 실행 |
| 18:00 | WORKLOG.md 한 줄 기록 (1~3줄, 결과만) |

---

**문서 끝**
