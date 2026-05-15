# Sales Cockpit PRD — 한도정밀 L2C

**v0.7** | 2026-05-07 | 발표 2026-05-14 | P0/P1/P2

> v0.7: ERP를 Apex Mock으로 일원화 (Beeceptor 제거, 외부 callout 0). 시연 즉석 ERP 동기화 버튼 (FR-ORDER-002 갱신). NG-017(Contract 미사용 — 단발 거래 한정) 신설.
> v0.6: OCR을 Prompt Builder 멀티모달로 전환 + FR-OPP-005(사업장 규모 자동 조사) 제거(NG-016 신설). NICE/한국기업데이터 상용 신용 API는 별도 계약 영역으로 격리.
> v0.5: AE 손 부담 줄이는 보강 2건 — **PHONE 통화메모 자동 추출**(LEAD-006), **재견적 자동 초안**(QUOTE-009).
> v0.4: 사업자등록증 OCR + 사업장 규모 조사를 **Lead → Opp 단계로 이동**.
> v0.3: 세금계산서 영역 제거(NG-014). Payment를 Order에 직접 연결.

---

## 1. 목적·범위

### 1.1 Goals

| ID | Goal |
|---|---|
| G-001 | AE가 Lead→미수금 시각화까지 단일 워크스페이스에서 처리 |
| G-002 | AE 입력 부담 90% 감축 (AI Quote + 사업자등록증 OCR + 회사정보 자동 보강) |
| G-003 | 영업·ERP·회계 책임 분리 (결재·생산·품질·자재·세금계산서 제외) |
| G-004 | 출고 후 분할 입금 추적 + 장기미수금 시각 강조 |
| G-005 | 한국 비즈니스 정서 (이름 단일, 한국식 직급 등) |
| G-006 | 단계 전이 게이트 — "다음 단계로 가려면" 페이지 명시 |
| G-007 | 시연 골든패스 6분 무결 수행 |

### 1.2 Out of Scope

| ID | 항목 |
|---|---|
| NG-001 | 자재 입출고·재고 |
| NG-002 | 작업지시·생산일정 (Mock 시그널만) |
| NG-003 | 품질검사 판정 |
| NG-004 | 매출인식·분개·VAT 신고 |
| NG-005 | 결제 처리(PG) |
| NG-006 | AR Aging BI |
| NG-007 | 모바일 네이티브 앱 |
| NG-008 | 다국어 메일 |
| NG-009 | 견적·Won·할인 결재 |
| NG-010 | 생산팀 인계 메일 |
| NG-011 | 미수금 자동 단계 메일 |
| NG-012 | 신용한도 발송 차단 |
| NG-013 | 상세 권한 시스템 |
| NG-014 | 세금계산서(홈택스) 발행 |
| NG-015 | **Lead 단계에서 사업자등록증 첨부 강제** (단순 견적 문의자에게 entry barrier) |
| NG-016 | NICE/한국기업데이터 등 상용 신용평가 API 연동 (별도 계약·라이선스 영역) |
| NG-017 | Master Contract 객체 사용 (정기 거래·call-off 패턴 — 본 릴리스는 단발 거래 한정) |

### 1.3 Why

> AE는 RFQ→입금까지 끝까지 책임지나 흐름은 메일·엑셀·메신저·ERP에 흩어짐. 통합 워크스페이스 + AI(자유 텍스트 영역만) + ERP/회계 Mock 격리로 입력 부담 90% 감축, Sales Cloud 색깔 유지. **Lead 단계는 가볍게(단순 문의 환영), Opp Discovery→Quote 단계에서 사업자등록증 OCR로 본격 보강**(현실 거래 관행과 일치). 신용 평가 영역(NICE 등)은 NG-016으로 명시 격리하여 영업·신용 책임 경계를 분명히 함.

---

## 2. 페르소나

**AE 김민수** (35세, 5년차) @ 한도정밀 — 거래처 30개, 월 RFQ 25건. 책임: Lead 인입→Qualify→Quote→Won→Order/납기→출고 등록→분할 입금 확인→미수금 시각 추적. **(책임 외)** 결재·인계·생산일정·세금계산서·매출인식.

Secondary: 영업 매니저(모니터링), 시스템 관리자.

---

## 3. 가정·제약

- A-001~002: Sales Cloud + Agentforce + Prompt Builder, Org "My_Org"
- A-003~005: **ERP는 Apex Mock 클래스 (외부 callout 0), OCR은 Prompt Builder 멀티모달, 회사정보(매출·신용점수)는 NG-016으로 격리**
- A-006: 한도정밀 가상. 시드: Account 30 / SKU 50 / 과거 Order 100
- A-007: 세금계산서는 외부 회계·홈택스 영역 (본 시스템 미연동)
- A-008: 사업자등록증은 Opp Discovery 단계에서 거래 의사 확인 후 교환된다고 가정 (Lead 단계 강제 X)
- A-009: 본 시연은 단발 거래 모델 (Won → Order 직접 생성). Master Contract·정기 call-off는 NG-017로 격리.
- C-001: Lightning Experience (한국어)
- C-002: 시연 6분 / 2026-05-14 오후

---

## 4. Functional Requirements

### 4.1 FR-LEAD

**FR-LEAD-001 — 3채널 인입 [P0]**
PHONE(콕피트 "전화 Lead 등록" LWC) / EMAIL(rfq@hando.example, 자동) / VISIT(콕피트 "방문 Lead 등록").
- [ ] `Source_Channel__c` Picklist (PHONE/EMAIL/VISIT)
- [ ] EMAIL 60초 이내 자동 생성
- [ ] PHONE/VISIT은 한국 정서 폼(§4.9)
- [ ] **Lead 단계는 가벼운 정보만 — 회사명·담당자·연락처·요청 부품**

**FR-LEAD-002 — RFQ 사양 자동 추출 [P0]**
EMAIL Lead 생성 시 Prompt Builder `SpecExtract`가 메일·첨부 텍스트에서 부품명·수량·재질·공차·납기 추출.
- [ ] JSON: `{partName, quantity, material, tolerance, requestedDate}`
- [ ] 신뢰도 < 0.6 시 AE 수동 입력 요청
- [ ] `Lead.RFQ_Spec_JSON__c`에 저장

**FR-LEAD-003 — Lead Scoring [P1]**
Apex `LeadScoringService`가 채널·수량·과거거래·요청 양 기반 가중평균 → 0~100. Hot(70+)/Warm(40~69)/Cold(<40).
*Note*: 사업장 규모 가중치는 Opp 단계 OCR 후 재계산(FR-LEAD-005).

**FR-LEAD-004 — Lead Convert 자동 매핑 [P0]**
Flow가 Account/Contact/Opp 자동. 중복키: 회사명 정규화. Opp Stage="Discovery". 사양 → Opp 복사.
- [ ] **Convert 게이트 가벼움**: 회사명 + 담당자 1+ + 사양 확정 (사업자번호 미요구)

**FR-LEAD-005 — Lead 우선순위 콕피트 [P0]**
Lead Priority Card에 미컨버전 Lead Score 내림차순. Hot/Warm/Cold 색상, 채널 아이콘, 24h+ 미처리 빨간 배지, 카드에서 직접 Convert.

**FR-LEAD-006 — PHONE 통화메모 자동 추출 [P0]**
PHONE Lead 등록 시 AE가 통화 메모(자유 텍스트, 예: "현대모비스 김 대리 010-xxxx-xxxx, 베어링 6204 100개, 다음달 말까지")를 입력하면 Prompt Builder `CallMemoExtract`가 회사명·담당자·연락처·요청 부품·수량·납기 추출 → LWC 폼 자동 채움.
- [ ] LWC `phoneLeadIntake`에 메모 입력 영역(textarea)
- [ ] "메모로 자동 채우기" 버튼 클릭 시 Prompt Builder 호출
- [ ] 추출된 항목은 폼 필드에 자동 입력 + 노란 점으로 표시 (AE가 검토)
- [ ] 신뢰도 < 0.6 시 수동 입력 안내
- [ ] 추출 실패 시 메모 보존, 폼 빈 상태 유지

---

### 4.2 FR-OPP

**FR-OPP-001 — Stage 정의 [P0]** Discovery → Quote Sent → Negotiation → Won → Lost. 표준 Probability.

**FR-OPP-002 — Stage 자동 전이 [P0]** Quote 발송→"Quote Sent". 응답 의도 "재견적/조건확인/일정조정"→"Negotiation". "수락"→AE 수동 Won.

**FR-OPP-003 — Stage별 권장 액션 [P1]** Opp 사이드바에 Stage 기반 액션 3개.

**FR-OPP-004 — 사업자등록증 OCR (Account 보강) [P0]**
Opp Discovery 단계에서 거래 의사 확인 후, AE가 Opp/Account 페이지에서 사업자등록증(이미지/PDF) 업로드 → **Apex가 Prompt Builder Template `BusinessLicenseExtract` 호출 (이미지 base64 → JSON 구조화)** → 사업자번호·회사명·대표자·주소·업종 자동 추출 → Account에 자동 채움.
- [ ] LWC `businessLicenseUpload` (Opp/Account 페이지에 임베드)
- [ ] 5초 이내 결과 표시
- [ ] 라인별 미리보기 + AE 확인
- [ ] 자동 채울 필드: `Account.Business_Number__c`, `Name`, `CEO_Name__c`, `BillingAddress`, `Industry`
- [ ] 파일은 Account의 ContentVersion으로 보존
- [ ] OCR 실패 시 AE 수동 입력 fallback
- [ ] **Dependency: Prompt Builder Template `BusinessLicenseExtract`, Models API 멀티모달 입력 지원**

**FR-OPP-006 — (T2) 입찰 채널 [P2]**

---

### 4.3 FR-STAGE — 단계 전이 게이트

**FR-STAGE-001 — 다음 단계 조건 페이지 명시 [P0]**
LWC `stageGateChecklist`가 객체별 게이트 표시.

| 객체 | "다음으로 가려면" |
|---|---|
| Lead → Convert | 회사명 / 담당자 1+ / 사양 확정 (**사업자번호 불필요**) |
| Opp Discovery → Quote | **사업자등록증 OCR 또는 사업자번호 직접 입력** / 사양 확정 / 키맨 1+ |
| Quote → 발송 | 라인 1+ / PDF 생성 |
| Order → 입금 추적 | 출고 완료 등록 |
| Order → 입금 완료 | 누적 Payment ≥ Total_Amount |

- [ ] ✅/❌ 시각화, 모두 ✅ 시 "다음 단계로" 활성화, ❌ 클릭 시 입력 필드 포커스

**FR-STAGE-002 — 게이트 미충족 차단 [P0]** 비활성 버튼에 "X 먼저 완료하세요" 툴팁.

---

### 4.4 FR-QUOTE

**FR-QUOTE-001 — AI Quote 초안 [P0]** "AI 견적 초안" 클릭 → 사양+카탈로그 매칭 → Quote/QuoteLineItem 자동 생성. Top 3 SKU 중 신뢰도 최상 1개. `AI_Draft_Confidence__c` 기록. 5초 이내 Quote Builder 전환.

**FR-QUOTE-002 — Quote Builder 인라인 편집 [P0]** LWC `quoteBuilder`에서 라인별 SKU·수량·단가·할인 인라인 수정. 변경 라인 좌측 노란 점. `AE_Edit_Count__c` 자동 증가.

**FR-QUOTE-003 — 할인 금액 입력 + % 자동 계산 [P0]**
할인은 **금액 입력**, % 자동 표시.
- [ ] 라인별 할인금액 칸 (₩)
- [ ] 입력 즉시 옆에 % 표시 (예: 40,000 → "1.36% 할인")
- [ ] 라인 금액 = 단가×수량 − 할인금액
- [ ] 예시: 49,000×60=2,940,000원, 할인 40,000 → 2,900,000원, 1.36%
- [ ] 할인율 ≥20% 노랑, ≥30% 빨강 (정보 목적, 발송 가능)

**FR-QUOTE-004 — Quote PDF [P0]** 한도정밀 한국식 양식 → ContentVersion 첨부. 생성 ≤3초.

**FR-QUOTE-005 — Quote 이메일 발송 [P0]** PDF 첨부 + 추적픽셀·링크 + 한국어 템플릿. **신용한도 차단 없음**. 발송 후 Status='Sent' / `Sent_Date__c` 갱신.

**FR-QUOTE-006 — 이메일 추적 [P0]** 픽셀→`Last_Opened_At__c`, 링크→`Last_Clicked_At__c`. 5초 이내 갱신.

**FR-QUOTE-007 — 응답 의도 분류 [P0]** Prompt Builder `IntentClassify` 6 카테고리(재견적/조건확인/거절/일정/확인/기타). EmailMessage.Intent__c. "재견적"→Negotiation, "거절"→Lost.

**FR-QUOTE-008 — 7일 무응답 follow-up [P1]** Sent 후 7일 무응답 시 AE Task + 메일 초안.

**FR-QUOTE-009 — 재견적 자동 초안 [P0]**
응답 의도가 "재견적"으로 분류되면(FR-QUOTE-007) Apex가 기존 Quote를 복제하고 Prompt Builder `RequoteDraft`가 응답 메일 본문을 분석하여 변경 사항(수량·할인·SKU)을 새 Quote 라인에 반영.
- [ ] 입력: 기존 Quote + QuoteLineItem + 응답 메일 본문
- [ ] 출력: 새 Quote(`Status='Draft'`), 변경된 라인은 좌측 황금 점
- [ ] AE에게 Bell 알림 + 콕피트 RFQ Card에 "재견적 초안" 카드 노출
- [ ] AE가 Quote Builder에서 검토 후 발송 (FR-QUOTE-005)
- [ ] 신뢰도 < 0.6 시 라인 변경 없는 단순 복제 + AE 수동 편집

---

### 4.5 FR-ORDER

**FR-ORDER-001 — Won 후 Order 자동 생성 [P0]** Stage='Won' 시 Order+OrderItem(QuoteLineItem 복사) 자동. Status='Activated'. 결재 의존성 없음.

**FR-ORDER-002 — ERP 생산일정 동기화 [P0]**
매일 03:00 KST Scheduled Apex가 진행 중 Order에 `IExternalErpService.getProductionSchedule(orderId)` 호출 → 일정·위험점수 갱신. **시연 가시성을 위해 콕피트 Order Risk Card에 "🔄 ERP 동기화" 버튼 제공 — AE/평가자가 즉석에서 동기화 트리거**.
- [ ] `ErpServiceMock` 구현 (외부 callout 없음, Apex 내부 분기)
  - orderId 끝자리 0~5 → 정시 (riskDays=0, status=OnTrack)
  - 끝자리 6~8 → 위험 (riskDays=1~4 안에서 결정적·미세 가변, status=AtRisk)
  - 끝자리 9 → 대형지연 (riskDays=5~8, status=CriticalDelay)
  - 날짜는 today 기준 상대값 (productionStartDate=today-3일, productionEndDate=today+7+riskDays, expectedShipDate=today+10+riskDays)
- [ ] Apex Invocable `OrderScheduleSync.runOnce(orderIds)` — Scheduled Cron + LWC 수동 버튼 공유
- [ ] Order.Last_ErpSync_At__c DateTime 갱신 (마지막 동기화 시각)
- [ ] 갱신 실패 시 매니저 알림 (Apex Exception 처리)

**FR-ORDER-003 — 납기 위험 점수 [P0]** Apex `DeliveryRiskCalculator` 0~100. ≥70 빨강 / 40~69 노랑 / <40 녹색.

**FR-ORDER-004 — 납기 사전 통보 [P0]** 위험 ≥70 + N-7 이내 시 AE Task + Prompt Builder `DelayNotice` 메일 초안(수주번호·약속일·예상지연일·재협상 옵션 3가지).

**FR-ORDER-005 — 분할 납품 시각화 [P1]** LWC `orderScheduleTracker` 간트/타임라인.

**FR-ORDER-006 — 출고 완료 등록 [P0]** AE 수동: 콕피트/Order 페이지에서 "출고 완료 등록" → `Production_Status__c='Shipped'` + `Shipped_Date__c`. 출고 메모 가능. 이 시점부터 입금 추적 가능. **세금계산서 발행은 외부**(NG-014). ERP에 별도 ack 호출 없음 (D17). SF 내부에서만 출고 완료 처리.

---

### 4.6 FR-AR

**FR-AR-001 — 분할 입금 추적 [P0]**
AE가 "입금 등록" → Payment__c 생성. 1 Order : N Payments.
- [ ] 입력: 입금일·입금액·메모
- [ ] Status='Paid' 자동
- [ ] Order 페이지에 누적 입금액·잔액 표시
- [ ] 누적 ≥ Total_Amount 시 "입금완료" 라벨
- [ ] 분할 이력 테이블 시각화

**FR-AR-002 — 장기미수금 자동 분류 [P0]** Daily 03:00 Scheduled Flow가 `Order.Shipped_Date+180일` 미입금 잔액 있는 Account → `Long_Term_Debtor__c=true`. 잔액 0 시 false 환원. **자동 메일 없음**(NG-011).

**FR-AR-003 — AR 잔액 정보 표시 [P1]** `Total_AR__c = Σ(Order.Outstanding_Amount__c)` (Activated 한정). Quote Builder 헤더에 "AR 잔액 / 신용한도 / 초과액". 한도 초과 시 빨간 표시, **발송 가능**.

---

### 4.7 FR-COCKPIT

**FR-COCKPIT-001 — Lightning App Page [P0]** "Sales Cockpit" Home, 3컬럼.

**FR-COCKPIT-002 — 5개 우선순위 카드 [P0]**

| 카드 | 표시 | 정렬 |
|---|---|---|
| RFQ (좌) | 미컨버전 Lead (3채널) | Score↓ |
| Quote Tracking (중) | 응답 없는 Quote (3일+) | 무응답일↓ |
| Order Risk (중) | 위험점수 ≥70 Order | D-day |
| AR Action (우) | 입금 약속 임박/연체 Order + 미수금 Account (장기 빨강) | 경과일↓ |
| Lead Priority (우) | 우선순위 Lead | Score |

카드별 카운트 배지 / 클릭 시 객체 페이지 / 빈 상태 placeholder.

**FR-COCKPIT-003 — Agentforce 입력창 [P0]** 콕피트 상단 자연어 입력창.

---

### 4.8 FR-AGENT

**FR-AGENT-001 — Topic·Action [P0]** Topic = `SalesCockpitAssistant`. Action 5개:

| Action | 입력→출력 |
|---|---|
| `getTodayPriorityList` | () → 5카드 요약 |
| `getOrderAtRisk` | (period) → 위험 Order |
| `getAccountSummary` | (accountId) → 거래·미수·키맨 (장기미수금 강조) |
| `draftFollowupEmail` | (quoteId) → 메일 초안 |
| `getCrossSellCandidates` (T2) | (accountId) → SKU 3개 |

5초 이내 응답, 객체 ID 링크 포함.

**FR-AGENT-002 — 컨텍스트 인식 [P1]** 현재 페이지 객체 ID 자동 컨텍스트.

---

### 4.9 FR-LOC — 한국 정서

**FR-LOC-001 — 이름 단일 [P0]** "이름" 한 필드 → Contact.LastName 저장 (FirstName 빈 값, Salutation 숨김). 표시도 LastName만.

**FR-LOC-002 — 한국식 직급·부서 Picklist [P0]**
- 직급: 사원/주임/대리/과장/차장/부장/이사/상무/전무/부사장/사장/대표이사/회장
- 부서: 영업팀/구매팀/자재팀/기술팀/품질팀/생산팀/경영지원/대표

**FR-LOC-003 — 통화·날짜·주소 한국 형식 [P0]** Locale ko_KR, Currency KRW, ₩ 천단위 콤마, YYYY-MM-DD, 한국 주소 형식. LWC 라벨·메일 모두 한국어.

**FR-LOC-004 — 사업자번호 검증 [P0]** XXX-XX-XXXXX 10자리 + 체크섬. 자동 하이픈 포맷팅.

---

## 5. Non-Functional Requirements

| 영역 | ID | 요구사항 |
|---|---|---|
| **PERF** | 001 | Quote Builder AI 초안 ≤5초 |
| | 002 | 콕피트 5카드 ≤2초 |
| | 003 | OCR ≤5초 |
| | 004 | API timeout 10초 + retry 1회 |
| | 005 | Quote PDF ≤3초 |
| | 006 | Agentforce ≤5초 |
| **SEC** | 001 | 외부 API는 Named Credential |
| | 002 | Apex `with sharing` |
| | 003 | LWC FLS·CRUD 검증 |
| | 004 | 사업자등록증 ContentVersion 표준 권한 |
| **AUDIT** | 001 | Quote 라인 변경 필드 히스토리 |
| | 002 | Long_Term_Debtor__c 변경 이력 |
| | 003 | Payment 등록 이력 보존 |
| **A11Y** | 001 | LWC SLDS 토큰 |
| | 002 | 키보드 네비게이션 |
| | 003 | WCAG AA 명도 |
| **USAB** | 001 | RFQ→발송 클릭 ≤5 |
| | 002 | 1건 처리 ≤3분 |
| | 003 | 1280×800 기준 |
| **LOC** | 001 | 화면 전부 한국어 |
| | 002 | 라벨·메시지·메일 한국어 |
| | 003 | Locale ko_KR / KRW |
| **TEST** | 001 | Apex Org-wide ≥85% |
| | 002 | 핵심 클래스별 ≥90% |
| | 003 | 핵심 LWC Jest |
| | 004 | HttpCalloutMock |
| | 005 | Flow 분기 모두 |

---

## 6. UI Requirements

### 6.1 UI-COCKPIT
3컬럼(30/40/30), 상단 Agentforce full-width, 카드 카운트 배지, 빈 상태 placeholder. 색상: 위험 #EA001E / 경고 #FE9339 / 정상 #04844B.

### 6.2 UI-QUOTE
좌측 라인 편집, 우측 PDF sticky. 컬럼: SKU·품명·수량·단가·**할인금액·할인율(자동)**·금액. AE 변경 라인 황금 점. 합계·세액·총액 sticky. 헤더에 AR 잔액/한도/초과액 정보(차단 X). AI 신뢰도<0.6 경고. 할인율 ≥20% 노랑, ≥30% 빨강. 신용한도(Credit_Limit__c)는 AE 수기 입력으로 채워짐 (FR-OPP-005 제거로 자동 채움 없음).

### 6.3 UI-AR — 장기미수금 시각 강조
- AR Action Card: "입금 약속 임박/연체 Order" + "미수금 Account" 두 섹션
- **장기미수금(180일+) Account 빨간 배경 + 빨간 띠**
- 90~179일 주황 띠
- Account 상세: Long_Term_Debtor__c=true 시 페이지 상단 빨간 띠 + "장기미수금 거래처" 라벨
- Account 목록 뷰: 장기미수금 빨간 행
- Order 페이지: 분할 입금 이력 테이블

### 6.4 UI-ORDER-RISK
**약속일 D-day 카운트다운, 위험 점수 게이지, "🔄 ERP 동기화" 버튼 (마지막 동기화 시각 표시), "사전 통보 메일" 버튼.**

### 6.5 UI-LEAD-INTAKE
콕피트 "전화 Lead" / "방문 Lead" 버튼 → LWC 모달 (한국 정서). **사업자등록증 첨부 영역 없음 — Lead는 가벼운 정보만**.

### 6.6 UI-LOC
"이름" 단일 필드 / 직급·부서 Picklist / 사업자번호 자동 하이픈 / ₩ 콤마 / YYYY-MM-DD.

### 6.7 UI-STAGE-GATE
객체 페이지 사이드바에 LWC `stageGateChecklist`. ✅/❌ 시각화 / 모두 ✅ 시 다음 단계 버튼 활성화 / ❌ 클릭 시 필드 포커스.

### 6.8 UI-OCR (Opp/Account)
드래그&드롭 / 진행률(업로드→OCR→완료) / 라인별 편집 / "확인" 버튼 → Account 자동 채움. **Opp/Account 페이지에 임베드** (Lead 페이지 아님).
※ OCR은 Prompt Builder 멀티모달로 처리. 응답이 늦을 경우 신뢰도 < 0.6 시 수동 입력 fallback (FR-OPP-004).

---

## 7. Data Requirements

### 7.1 커스텀 객체

| ID | 객체 | 핵심 필드 |
|---|---|---|
| DR-OBJ-001 | `Payment__c` | `Order__c` (Lookup, 필수), `Paid_Date__c`, `Paid_Amount__c`, `Memo__c`, `Status__c` |
| DR-OBJ-002 (T2) | `Bid_Notice__c` | T2 |

> v0.2 `Invoice__c` 제거 (NG-014). Payment는 Order 직접 연결.

### 7.2 표준 객체 커스텀 필드

| 객체 | 필드 | 타입 | 용도 |
|---|---|---|---|
| Account | Business_Number__c | Text(12) | 사업자번호 (OCR 또는 수기) |
| Account | CEO_Name__c | Text | 대표자 |
| Account | Total_AR__c | Currency | 총 미수금 (Apex) |
| Account | Long_Term_Debtor__c | Checkbox | 장기 플래그 |
| Account | External_Credit_Score__c | Number | **외부 신용점수 (NG-016: 향후 NICE 등 계약 시 채움. 본 릴리스에서는 빈 값 또는 AE 수기 입력)** |
| Account | Credit_Limit__c | Currency | 신용 한도 |
| Lead | Source_Channel__c | Picklist | PHONE/EMAIL/VISIT |
| Lead | Lead_Score__c | Number | |
| Lead | RFQ_Spec_JSON__c | Long Text | Prompt 추출 |
| Quote | AI_Draft_Confidence__c | Number | |
| Quote | AE_Edit_Count__c | Number | |
| Quote | Sent_Date__c | DateTime | |
| Quote | Last_Opened_At__c / Last_Clicked_At__c | DateTime | 추적 |
| QuoteLineItem | Discount_Amount__c | Currency | 할인 금액 |
| QuoteLineItem | Discount_Percent__c | Percent (Formula) | 자동 계산 |
| Order | Production_Status__c | Picklist | Pending/InProgress/Done/Shipped |
| Order | Production_Start_Date__c / End_Date__c | Date | ERP Mock |
| Order | Delivery_Risk_Score__c | Number | 0~100 |
| Order | Shipped_Date__c | Date | AE 수동 |
| Order | Outstanding_Amount__c | Currency (Formula) | Total − Σ Paid |
| Order | Last_ErpSync_At__c | DateTime | 마지막 ERP 동기화 시각 (FR-ORDER-002) |
| Contact | Korean_Title__c | Picklist | 직급 |
| Contact | Korean_Department__c | Picklist | 부서 |
| EmailMessage | Intent__c | Picklist | 6 카테고리 |

> v0.4: Lead.Business_License_Uploaded__c 제거. 사업자등록증은 Account의 ContentVersion에 저장.

### 7.3 시드 데이터
Product2 50 / Account 30 (한국 가상) / Contact 60 (한국 이름·직급) / 과거 Order 100 (일부 Shipped) / Payment (분할+장기미수 시나리오) / 사업자등록증 샘플 5건.

---

## 8. Trace Matrix

### 8.1 Pain Point ↔ FR

| Pain | FR |
|---|---|
| #1 RFQ 인입 (3채널) | LEAD-001/002/006 |
| #2 신규 고객사 깜깜이 | LEAD-003/005, OPP-004 |
| #3 Quote 작성 수작업 | QUOTE-001/002/003/004 |
| #4 한국 정서 부재 | LOC-001~004, UI-LOC |
| #5 Quote 추적 깜깜이 | QUOTE-005/006/007/008/009 |
| #6 단계 전이 모호 | STAGE-001/002, UI-SG |
| #7 납기 위험 통보 | ORDER-002/003/004 |
| #8 출고→입금 추적 | ORDER-006, AR-001 |
| #9 분할 입금 | AR-001 |
| #10 장기미수금 시각 | AR-002, UI-AR-002~005 |

### 8.2 시연 골든패스 ↔ FR

| 단계 | FR |
|---|---|
| 1. 콕피트 열기 | COCKPIT-001/002/003 |
| 2. 전화 Lead 등록 + **통화메모 → AI 자동 채움** | LEAD-001/006 |
| 3. Lead Convert (가벼운 게이트) | LEAD-004, STAGE-001 |
| 4. **Opp Discovery → Quote 게이트에서 사업자등록증 OCR (Prompt Builder)** | OPP-004, STAGE-001 |
| 5. AI Quote + 할인 금액 입력 | QUOTE-001/002/003 |
| 6. Quote 발송 | QUOTE-005/006/008 |
| 7. 응답 의도 분류 → 재견적이면 **자동 초안**, 수락이면 Won → Order 자동 | QUOTE-007/009, OPP-002, ORDER-001 |
| **8. ERP 동기화 즉석 트리거 → 위험 5건 등장 → 사전 통보 메일** | ORDER-002/003/004 |
| 9. 출고 등록→분할 입금 | ORDER-006, AR-001 |
| 10. 장기미수금 빨간 표시 + Agentforce 질의 | UI-AR-002~005, AGENT-001 |

---

## 9. Definition of Done

- [ ] **P0 FR 33개 구현 완료**
- [ ] NFR-PERF-001~006 충족
- [ ] Apex 커버리지 ≥85%
- [ ] 한국어 UI 전수 점검
- [ ] 시연 골든패스 10단계 무결
- [ ] 한국 정서·장기미수금·OCR(Opp 단계)·분할 입금 시연
- [ ] 모든 P0 인수 조건 ✅
- [ ] 시드 데이터 6종
- [ ] PRD self-review 통과

---

## Appendix A — 우선순위

| | 카운트 |
|---|---|
| P0 | **33** |
| P1 | 6 |
| P2 | 1 |

**v0.7 | P0 카운트 변동 없음 (FR-ORDER-002 동작 방식 갱신: Beeceptor → Apex Mock + 즉석 동기화 버튼). NG-017 추가.**
v0.5→v0.6: P0 -1 (FR-OPP-005 사업장 규모 자동 조사 제거 — NG-016 격리).
v0.4→v0.5: P0 +2 (FR-LEAD-006 PHONE 메모 추출, FR-QUOTE-009 재견적 자동 초안).
v0.3→v0.4: OCR 2개 P0가 LEAD에서 OPP로 이동 (총 카운트 변동 없음).

## Appendix B — 시연 흐름 요약

```
1. 콕피트 (5카드)
2. 전화 Lead 등록 → 통화메모 자유 텍스트 → "메모로 자동 채우기" → 회사명·담당자·연락처·부품·수량 자동 폼 채움
3. 단계 게이트 → Lead Convert (사업자번호 미요구)
4. Opp Discovery → "Quote 작성 게이트"에 막힘 → 사업자등록증 PDF 업로드 → Prompt Builder OCR로 Account 자동 보강 → 게이트 ✅
5. AI Quote 초안 → 할인 40,000 → 자동 1.36%
6. Quote 발송 (한도 정보 표시만)
7. 응답 "재견적" → 자동 초안 생성 → AE 검토 → 재발송 → 응답 "수락" → Won → Order 자동
8. 콕피트 Order Risk Card → [🔄 ERP 동기화] 클릭 → 위험 5건 등장 → 78점 Order의 [사전 통보 메일] → 발송
9. 출고 등록 → 분할 입금 3회 → 잔액 추적
10. 장기미수금 빨간 표시 + Agentforce 자연어 질의
```

---

**문서 끝**
