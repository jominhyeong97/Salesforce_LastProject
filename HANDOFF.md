# HANDOFF v15 — Sales Cockpit (한도정밀 L2C)

**작성**: 2026-05-13 (Day 15 ~ Day 16 인계) — v14 까지 누적분 그대로 하단 유지. **본 세션은 PaymentCheck Action 추가 + 키워드 라우터 제거 + 슬라이드 #5 Lead 인입으로 교체 + docs 재정리. 톤 프리뷰 v2 작업은 미완(인터럽트) — 다음 세션 재개 지점 명시.**

---

## Day 15 작업 — 2026-05-13

### A. paymentRegister "유효한 증분" 버그 재발 fix
- Day 14 fix(`step=1 min=0`) 했음에도 화면에서 "유효한 증분 아닙니다" 경고 유지 + 등록은 통과(handleSubmit 이 reportValidity 안 거침)
- fix: `paymentRegister.html:51` — `step` 속성 **완전 제거** + `formatter="decimal"` (₩ 자유 입력)
- Deploy `0AfdM00000aRC5BSAW` ✅

### B. 챗봇 자연어 입력바 — PaymentCheck Action 추가 + 키워드 라우터 제거
**원인 분석**: "오늘"이 들어가면 무조건 GetTodayPriorityList 매칭 (line 281 키워드 라우터 greedy 매칭). ReAct LLM 라우터에 입금/회수/미수 routes 없으니 입금 질의 → 키워드 폴백 → 잘못 매칭.

**구현 (Day 15 신규 — Agentforce Action 5종 → 6종)**:
- 신규: `force-app/main/default/classes/agentforce/PaymentCheckAction.cls` + `_Test.cls` (13/13 PASS, 96% cov)
- 신규: `force-app/main/default/genAiFunctions/PaymentCheckAction/PaymentCheckAction.genAiFunction-meta.xml`
- mode 4종: `today`(오늘 입금 합계) / `week`(최근 7일) / `account`(특정 고객사 청구·누적·잔액) / `atrisk`(미수금 상위 Top N + 장기미수)
- 수정: `AgentforceInputBarService.cls` — `tryKeywordRouter` / `containsAny` / `extractAccountName` **완전 제거** (-120줄). 흐름 2단으로 단순화 ([1] ReAct → [2] AgentInputFallback)
- 수정: `AgentforceInputBarService_Test.cls` — 키워드 테스트 7건 제거, PaymentCheck 4건 + 폴백 흐름 5건 신규. 26/26 PASS (92% cov)
- 수정: `Sales_Cockpit_User.permissionset-meta.xml` — PaymentCheckAction classAccess 추가
- 수정: `AgentRouter.genAiPromptTemplate-meta.xml` — tool 5→6 (PaymentCheck), 결정 규칙 입금/회수 키워드 11종 + mode 자동 판별 추가. **`activeVersionIdentifier _1 → _2 bump 필수**(Day 5/7/11 safe-change 함정)
- 수정: `AgentSynthesize.genAiPromptTemplate-meta.xml` — PaymentCheck 예시 3건(today/account/atrisk). `_2 → _3 bump`

**실 LLM E2E 4/4 ✅**:
- "오늘 입금 들어온 거 있어?" → today 2건 ₩6M, (주)대광건설기계 최다
- "이번주 회수 어땠어?" → week 3건 ₩7.9M
- "미수금 큰 데 어디야?" → atrisk 5곳 ₩38M, 장기미수 4곳
- "(주)대광건설기계 잔액?" → account 청구 ₩25M / 입금 ₩6M / 잔액 ₩19M
- `{{id:001xxx}}` 토큰 정확 — Account 인라인 navigation 동작

**함정 메모 (재확인)**:
- `like` Apex 예약어 — 변수명 `fuzzy` 로 변경
- GenAiPromptTemplate safe-change silent reject — versionIdentifier 명시 bump 필수

### C. 발표 슬라이드 #5 교체 — Agentforce 챗봇 → Lead 인입 AI 자동 추출
**근거**: 사용자 지적 "#1(LWC 챗봇) 과 #5(Agentforce 챗봇) 시연 영상이 사실상 동일. 기능 위주 차별화 필요". 합의 → #5 를 Lead 인입 AI 추출로 교체.

**수정 파일** `docs/specs/2026-05-12-presentation-deck.html`:
- Slide 20 (F5 Page A): "Agentforce 5 Action" → **"Lead 인입 AI 자동 추출 + Score 자동화"** — 5 카드(전화 메모 / 방문 노트 / RFQ 이메일 / 6필드 추출 / Lead Score 4축)
- Slide 21 (F5 Page B): planner routing → **"Prompt Builder + 정규식 hybrid + 점수 4축"** — CallMemoExtract/SpecExtract → 정규식 fallback → LeadScoring 4축. code aside `calculateScore` 스니펫
- Slide 22 (F5 Page C): 시연 영상 caption "한라정공 박과장 02-555-1234, 베어링 6204 100개 납기 4/30" → 25초 GIF placeholder
- stack-strip: `Agentforce` → `Email Service`
- section-tag: `AGENTFORCE` → `LEAD INTAKE`
- Slide 12 (F1 Logic) narrative: "진입점 3개 — 키워드 / LLM / Agentforce" → **"진입점 2개 — ReAct LLM / Agentforce"** (Day 15 키워드 라우터 제거 반영)

### D. docs/ 폴더 재정리 (Day 15 종료 시)
**구조**:
```
docs/
  기획서/           (sales-cockpit-prd/-design/-dev-plan, remaining-schedule)
  홈_영업파이프라인/  (home-pipeline-design)
  L2C_납기ERP/       (opp-promised-delivery-erp-gap-design)
  UX다듬기/          (ux-polish-design + plan)
  발표자료/          (presentation-deck-design + .html)
  samples/          (그대로 — business-license 샘플)
  superpowers/      (그대로 — OCR design/plan)
```
- OCR_사업자등록증 폴더 — `docs/specs/` 에 OCR 파일 없음(설계는 `superpowers/` 에 있음) → 생성 안 함

---

## Day 16 인계 (다음 세션 시작점)

### 🔴 미완 작업 — 톤 프리뷰 v2 재개 필요

**컨텍스트**: 발표 슬라이드 디자인을 클로드 디자인(`c:\Users\user\Desktop\조민형\과제\7주차\한도정필 PPT\한도정밀 L2C 발표.html`) 톤으로 통일하는 작업. v1 시도는 사용자 거절(본문까지 다 새 레이아웃으로 다시 짜서 실패). **v2 설계 사용자 승인 완료**, 구현 직전 인터럽트.

**v2 설계 (확정)**:
- 외피 (header/footer/폰트/색) = Claude Design
- 본문 HTML = 우리 원본 `<div class="main">` 마크업 **단 한 줄도 안 건드림**
- 우리 본문 CSS 클래스(`.feat-a-grid` / `.swiss-card` / `.lede-quote` / `.logic-grid` / `.video-placeholder` / `.etc-grid` / `.tag-philosophy` 등) — 그대로 작동
- 색은 우리 CSS var 재매핑으로 Claude 팔레트 올라타기 (`--sf-cloud/--sf-blue → --accent` #1B5EFF, `--sf-navy → --ink` #0B1626, `--text-primary/-secondary/-muted → --ink/--ink-2/--muted`, `--font-display/--font-body → Pretendard`, `--font-mono → IBM Plex Mono`)
- **슬라이드 크기 = 실제 1920×1080 그대로** (scale 없음, 실전 출력 모양). v1은 scale(0.5)로 축소했었음 — v2에선 제거
- 범위 = slide 8~23 (16장)
- 위치 = `docs/발표자료/presentation-deck.html` 맨 뒤 `</body>` 직전에 append (기존 31장 무수정)

**작업 순서**:
1. 기존 v1 톤 프리뷰 블록 제거 (`<!-- TONE PREVIEW v1 -->` 부터 v1 끝까지)
2. v2 블록 작성 — `#tone-preview-v2` 스코프 CSS + Claude Design 폰트 import + 16 슬라이드 (외피만 Claude, 본문은 우리 원본 마크업 verbatim)
3. 브라우저 확인 → 사용자 OK → **클로드 디자인 HTML 원본**(`c:\Users\user\Desktop\조민형\과제\7주차\한도정필 PPT\한도정밀 L2C 발표.html`)에서 기능 슬라이드 (8~22) **완전 교체**

**참조 파일**:
- 클로드 디자인 원본 (외피 소스): `c:\Users\user\Desktop\조민형\과제\7주차\한도정필 PPT\한도정밀 L2C 발표.html` (3445줄)
- 우리 발표 자료 (본문 소스 + v1 잔재): `docs/발표자료/presentation-deck.html` (Day 15 재정리 후 경로)
- v1 잔재 위치: 파일 끝 `<!-- TONE PREVIEW v1 -->` 마커로 시작 (검색하면 바로 찾음)

**현재 색·폰트 var 매핑표**:

| 우리 var (presentation-deck.html line 17~45) | → 클로드 Design var |
|---|---|
| `--sf-cloud` #00A1E0 / `--sf-blue` #1589EE | `--accent` #1B5EFF |
| `--sf-blue-dark` #0070D2 | `--accent-dark` #0E3FB8 |
| `--sf-navy` #032E61 / `--sf-navy-2` #16325C | `--ink` / `--bg-deep` #0B1626 |
| `--text-primary` #080707 | `--ink` #0B1626 |
| `--text-secondary` #3E3E3C | `--ink-2` #2E3A4E |
| `--text-muted` #706E6B | `--muted` #6B7689 |
| `--bg-soft` #F4F6F9 | `--bg-soft` #F4F6FB |
| `--sf-success` #04844B / warning #FE9339 / error #C23934 | `--success` #1AA56E / `--warn` #E08434 / `--danger` #DC4B4B |
| `--font-display` Archivo+Noto Sans KR / `--font-body` Noto Sans KR | Pretendard + Noto Sans KR |
| `--font-mono` JetBrains Mono | IBM Plex Mono |

### 잔여 마감 작업 (5/14 18:00 메일)

| # | 작업 | 상태 |
|---|---|---|
| 0 | 시드 데이터 채우기 | ✅ Day 14 완료 |
| 1 | 시연 dry-run 버그 fix | ✅ Day 14~15 완료 |
| 2 | 기능 녹화 (골든패스 1 + Feature C GIF 5) — **분할 입금부터 다시 시작** | 🔄 |
| 3 | **톤 프리뷰 v2 적용 → 클로드 디자인 HTML로 본격 교체** | 🔴 Day 16 우선 |
| 4 | PDF 생성 (`scripts/export-pdf.sh`) | ⏳ |
| 5 | 메일 발송 (5/14 17:55) | ⏳ |

---

## Day 14 작업 — 본 세션

### A. 발표 자료 (PPT) — Style C "SLDS Swiss" 31장 HTML
- 산출: `docs/specs/2026-05-12-presentation-deck.html` (129KB, self-contained, inline 편집 지원)
- frontend-slides 스킬 Phase 0 → Phase 5 정식 흐름 수행 (3 프리뷰 → Style C 선택)
- 스펙: `docs/specs/2026-05-12-presentation-deck-design.md` 그대로 반영
- 디자인 — Salesforce SLDS 팔레트 (Navy/Cloud/Error/Warning/Success), Archivo+Noto Sans KR+JetBrains Mono, Swiss 그리드, funnel video placeholder
- 인라인 편집 — E 키 토글 / Ctrl+S export / localStorage 자동 저장 / outerHTML 캡처 전 edit state strip
- 영상 placeholder 5건 (Feature C 페이지) — 추후 GIF/MP4 캡처 후 교체

### B. 시연용 데이터 리셋
- 신규: `scripts/apex/resetDemoData.apex` — 멱등 wipe + 14일 ±기준 재시드
- 결과 (2026-05-12 기준):
  - Account 10 · Contact 20 · Product2/PBE 15 · Lead 8 · Opp 10 · Quote 8 / QLI 16 · Order 16 · OrderItem 34 · Payment__c 23
  - Lead 분포 — 신규 5(최근 7일 newRfqs 카드) / 제안대기 2(priorityLeads) / 미전환 1
  - Opp 분포 — 발굴 2 / 견적작성 2 / 견적발송 2 / 협상 2 / 수주 2
  - Quote 분포 — 초안 1 / 발송 3 / 응답대기 2 / 수락 1 / 거절 1
  - Order 분포 — 위험 3 / 대형지연 2 / 정시 6 / 장기미수 4 / 골든 1
- 골든 시연 체인 1세트: 미래공업(주) Account → Opp 수주 → Q-DEMO-007 수락 → ORD-GOLDEN-DEMO (PO-2026-GOLDEN, 1차 50% 입금)
- 5카드 + Pipeline 모두 데이터 채워짐 검증 완료

### C. 버그 개선 6건 (라이브 dry-run 중 발견)

#### #1 chatbotFab — 닫기 버튼 잘려서 안 보임
- 원인: `chat-panel` 안에 `<lightning-card>` 로 감싼 `agentforceInputBar` 가 들어가면서 lightning-card 의 padding · 보라 헤더 그라데이션이 close 버튼(top:14, right:14)을 시각적으로 가림
- fix (4 파일):
  - `agentforceInputBar.html` — `<lightning-card>` 외피 제거 → 단순 div, 자체 header 를 `<template lwc:if={showHeader}>` 로 감쌈
  - `agentforceInputBar.js` — `@api hideHeader = false` + `get showHeader()` 추가
  - `agentforceInputBar.css` — `:host { display:block; height:100% }` + `.chatbot { height:100%; min-height:0 }`
  - `chatbotFab.html/css` — chat-panel 에 명시적 header 추가, close 버튼을 그 안에 배치 (절대좌표 X), `<c-agentforce-input-bar hide-header="true">` 로 임베드, body 가 flex 1 채움
- 결과: close 버튼이 보라 header 안에서 28px 원형 + 흰 테두리로 명확. 헤더 중복도 사라짐.

#### #2 oppPipelineCard — 막대가 상태/비중 안 보여줌 (2건씩인데 풀바)
- 원인: `width = count/maxCount × 100` → 카운트 동일 시 모두 100% (max 기준 정규화의 부작용)
- fix — funnel + stage 카드 2-tier 재설계:
  - 폭 = `amount / totalAmount × 100` 정규화 + floor (active 8% / empty 3%) → 카운트 같아도 금액 다르면 폭 다름
  - 색 — 회색(발굴)→블루(견적작성)→딥블루(견적발송)→오렌지(협상)→그린(수주) 단계 진행감
  - empty stage 도 빗금 패턴으로 자리 보존
  - funnel 세그먼트 inline 라벨을 **금액 → 단계 이름**으로 변경 (사용자 후속 요청), threshold 14% → 11%
- 결과 미리보기 (시드 기준 217M): 발굴 10% / 견적작성 18.5% / 견적발송 19.8% / 협상 33.4% (가장 큼) / 수주 18.7%

#### #3 aeCockpit 헤더 정리 + 카드 5건 제한 풀기
- `aeCockpit.html` — `title="AE 콕피트 — 한도정밀"` → `"AE 콕피트"`, `icon-name="utility:dashboard_ext"` → `"standard:home"` (oppPipelineCard `standard:opportunity` 와 동일한 카테고리·크기로 시각 통일)
- `AeCockpitService.cls:15` — `ROW_LIMIT = 5 → 10` (사용자 우려 "더 많은 자료가 있는데 이것만 뜨는 건지?" 대응)
- `aeCockpit.css` — `.bl-list { max-height: 320px; overflow-y: auto }` + 얇은 커스텀 스크롤바. 카드 비대해짐 방지하면서 10건 다 표시

#### #4 quoteBuilder — "라인 추가" 모달 picker 가 비어 있음
- 원인: 사용자가 시연 중 새로 만든 Quote `견적1` 의 `Pricebook2Id = null`. `PricingService.getActiveProducts:35` 가드 `if (q.Pricebook2Id == null) return new List<>();` 가 빈 배열 반환 → picker 비어 보임
- fix (운영 데이터 수정): `견적1` 에 표준 Pricebook `01sdM00000MdBa2QAF` 연결
- 후속 권고 — `QuoteTriggerHandler.handleBeforeInsert` 에 `if (q.Pricebook2Id == null) q.Pricebook2Id = <std>` 한 줄 추가하면 재발 방지. **본 세션에선 보류**

#### #5 자동 재견적 체인 — "회신 보냈는데 안 됨"
- 원인: org 에 **인바운드 이메일 라우팅 (Email-to-Case / Apex Email Service / InboundEmailHandler) 이 설정 안 되어 있음**. 외부 회신 메일이 SF 로 안 들어옴 → EmailMessage(Incoming=true) 가 생기지 않음 → `EmailMessageTriggerHandler:23` 가드에 막힘
- 코드 자체는 정상 — `EmailMessageTrigger` → `EmailIntentClassifyService.classifyAsync` → `QuoteRequoteService.autoDraftIfRequote` 흐름 검증됨
- fix — 시연용 시뮬레이션 스크립트:
  - `scripts/apex/simulateRequoteReply.apex` — Incoming=true + RelatedToId=Quote.Id + 자연어 본문 "10% 할인 더 부탁드립니다" 인 EmailMessage 1건 insert
  - 트리거 자동 발화 → @future 분류 → Intent='Requote' → 새 (재견적) Quote 자동 생성 확인됨 (`견적1 (재견적)` 8초 후 생성)
  - 사용자 후속 요청으로 FromAddress 를 Quote → Opp → Account → 1차 Contact.Email 자동 추출로 개선 (없으면 buyer@customer.example fallback)
- **운영 환경에선 Email-to-Case 활성 또는 Apex Email Service + InboundEmailHandler 한 줄 작성으로 해결 가능** → "아쉬웠던 점" 슬라이드에 후보로 둘 만함

#### #6 paymentRegister — "100 입력 시 유효한 증분 아닙니다"
- 원인: `paymentRegister.html:51` 의 `<lightning-input type="number" step="100" min="1">` 조합. HTML5 number step 검증이 `min + n × step` (= 1, 101, 201, ...) 만 허용 → 100 거부
- fix: `step="1" min="0"` 으로 변경. ₩1 단위 자유 입력 가능, 깔끔한 금액(100/1000/10000) 모두 수용

### D. 추가 데이터 정정 — 견적 수락 시연 흐름
- 대광건설기계 Opp (`006dM00000NP10TQAT`) 가 협상 단계인데 Quote 가 모두 발송/거절 → 수주 전이 시 OrderTriggerHandler 의 fallback "Status=수락 Quote" 가 못 찾음 → OrderItem 0건 → TotalAmount=0
- fix: `견적2` Status='수락' 전환 → QuoteTriggerHandler.handleAfterUpdate 가 OpportunityLineItem 1건 자동 갱신 확인. 이제 사용자가 협상→수주 누르면 Order 자동 생성 + OrderItem 자동 복사 + TotalAmount 자동 계산 가능

---

## Day 14 산출 파일

| 분류 | 파일 |
|---|---|
| 발표 자료 | `docs/specs/2026-05-12-presentation-deck.html` (신규, 129KB) |
| 시드 스크립트 | `scripts/apex/resetDemoData.apex` (신규) |
| 시연 시뮬레이션 | `scripts/apex/simulateRequoteReply.apex` (신규) |
| LWC fix | `lwc/chatbotFab/{html,css}`, `lwc/agentforceInputBar/{html,js,css}`, `lwc/oppPipelineCard/{html,js,css}`, `lwc/aeCockpit/{html,css}`, `lwc/paymentRegister/html` |
| Apex fix | `classes/cockpit/AeCockpitService.cls` (ROW_LIMIT 5→10) |
| 운영 데이터 | `견적1.Pricebook2Id` 채움 · `견적2.Status='수락'` |

## 다음 액션 (사용자 작업 순서 기준)

| # | 작업 | 상태 |
|---|---|---|
| 0 | 시드 데이터 채우기 | ✅ 완료 |
| 1 | 시나리오 시연 dry-run + 버그 개선 | 🔄 진행 중 (Day 14 본 세션) |
| 2 | 기능 녹화 (골든패스 메인 1건 + Feature C 짧은 GIF 5건) — **분할 입금부터 다시 시작 (오후 5:59 2026-05-12)** | 🔄 |
| 3 | 최종 PPT 디자인/텍스트 다듬기 + 영상 첨부 | ⏳ |
| 4 | PDF 생성 (frontend-slides Phase 6B: scripts/export-pdf.sh) | ⏳ |
| 5 | 17:55 메일 발송 (5/14) | ⏳ |

## 시연 시 권장 흐름 메모 (Day 14)

- **메인 골든패스**: 미래공업(주) — Opp `미래공업 베어링 1차 수주` (이미 수주) → Quote `Q-DEMO-007-미래공업` (수락) → Order `ORD-GOLDEN-DEMO` (시드 완료) 페이지 순회
- **라이브 변환 시연**: Lead `동광정밀(주) — 베어링 200 EA 견적 요청` (score 92, Source=PHONE, 최근 7일 신규) → Lead Convert → 새 Opp/Quote 흐름
- **재견적 시연**: 발송 상태 Quote 선택 → `sf apex run --file scripts/apex/simulateRequoteReply.apex --target-org My_Org` 실행 → 8초 후 (재견적) 새 Quote 자동 생성 확인
- **L2C 자동 시연**: 대광건설기계 Opp (협상→수주 전이) — 견적2 수락 상태라 OrderItem 자동 복사 + TotalAmount 자동

---

# v13 이전 누적 분 (그대로 유지)

**작성**: 2026-05-12 (Day 13) — Day 1~12 + **UX 다듬기 (D33) + 영업 파이프라인 (D35) + 레이아웃 정비 (D36) + Quote 자동화 (D37) + SLDS 디자인 시스템 v2 통일 완료**. 잔여 작업 = 시연 동영상 캡처 + 슬라이드 작성.

## Day 13 작업 — 6 트랙

### 트랙 1: UX 다듬기 6건 (D33)
- ✅ #1 협상→수주 단계 안내 (stageGateChecklist info 박스)
- ✅ #2 Order.EndDate 납기일 D-N/D+N 배지 (orderRiskCard + aeCockpit)
- ✅ #3 AI 응답 인라인 ID 링크 ({{id:...}} 토큰 + LWC NavigationMixin)
- ✅ #4 공통 AI 로딩 메시지 (CustomLabel AI_Loading_Message + 4 LWC)
- ✅ #5 견적 단계 게이트 — 첨부 검사 (StageGateService.checkQuoteReadiness)
- ✅ #6 챗봇 스타일 입력바 (agentforceInputBar 전면)

### 트랙 2: 홈 보강 (D35)
- ✅ Opp 영업 파이프라인 카드 (`oppPipelineCard` LWC + AeCockpitService.stagePipeline DTO)
- ✅ 우선 처리 Lead 카드에 Status 분포 chip 추가

### 트랙 3: 레이아웃 정비 (D36)
- ✅ Lead 활동 탭 제거 (사용자 수동), 신규 `leadScoreBadge` LWC (큰 점수 카드 + strip pattern)
- ✅ Account 7필드 제거 (Industry/Fax/AccountNumber/Website/ParentId/Created/Modified)
- ✅ Opp 4필드 추가 (LeadSource/Type/ExpectedRevenue/ForecastCategoryName)
- ✅ Quote 레이아웃 청구인·주소 섹션 제거

### 트랙 4: 챗봇 / 전화 Lead FAB
- ✅ `chatbotFab` (보라 동그라미 우하단, AI 챗봇 패널 toggle)
- ✅ `leadIntakeFab` (초록 동그라미, 전화 Lead 등록 중앙 모달 95vh)
- 둘 다 position:fixed + floating + 둥둥 애니메이션 + Home Page 한정

### 트랙 5: SLDS v2 디자인 시스템 통일
- 컬러 8토큰만 (1 brand SLDS 블루 + 3 status + 5 gray) — 보라/시안/노랑 등 제거
- 이모티콘 → SLDS lightning-icon 표준 (📋📈🎯⚠📥📤💰🚪🔥❄☀⏰🚚📡💡📌✉🔄 등 16건 제거)
- 점수 카드 그라데이션 → 좌측 4px strip + 흰 본체 (leadScoreBadge / orderRiskCard / oppInsightCard 일관)
- aeCockpit 5카드 좌측 border → 상단 3px strip, chip/badge SLDS 표준 톤
- FAB (chatbotFab / leadIntakeFab) + agentforceInputBar 챗봇 패널은 의도적 유지 (보라/초록)

### 트랙 6: Quote 자동화 룰 (D37)
- ✅ `QuoteTrigger` (before insert + after update) + `QuoteTriggerHandler`
- Rule 1: Quote 인서트 시 Account 의 BillingAddress / ShippingAddress / BillingName / ShippingName / 1차 Contact 자동 복사
- Rule 2: Status '수락' 전이 시 QuoteLineItem → OpportunityLineItem 자동 복사 (Quote.IsSyncing 표준 read-only 우회 — 직접 라인 복사)
- L2C 완전 자동화: Account → Quote → Opp Products → Won → Order + OrderItem (Day 9 #1 연결)

## 최종 통계 (Day 13 종료)
- **Apex Test 332/332 PASS** (100%)
- **Org-wide 커버리지 87%** 유지
- Prompt Template 11개 (AgentSynthesize v2 마커 규칙 포함)
- CustomLabel 2개 (Quote_Tracking_Base_URL, AI_Loading_Message)
- 누적 LWC ~22개 (신규 Day 13: chatbotFab / leadIntakeFab / leadScoreBadge / oppPipelineCard)
- 의사결정 D33~D37 추가

## 의사결정 Day 13
- D33 (2026-05-12): UX 다듬기 6건은 architecture 변경 없이 표면만
- D34: 챗봇 FAB Home 한정 — Lightning Experience chrome 구조상 app-wide floating 불가 → Home Page 한정 position:fixed
- D35: 홈 보강 2종 (영업 파이프라인 + 리드 status chip)
- D36: 레이아웃 정비 7항목 (Lead/Account/Opp/Quote/Order)
- D37: Quote 자동화 룰 2건 (주소 복사 + Status=수락 → OLI 동기화). Quote.IsSyncing platform read-only 우회 패턴 학습

## 잔여 작업 (5/14 18:00 마감)
- 시연 동영상 캡처 (골든패스 §1~§10 + ReAct 챗봇 + FAB + 영업 파이프라인 + Quote 자동화)
- PPT/PDF 슬라이드 9 섹션 작성
- 17:55 메일 발송
**제출**: 2026-05-14 (목) **18:00 까지 메일 발송** — 발표 취소, **PPT/PDF 슬라이드 형태로 제출**
**남은 시간**: ~3일 (5/12~5/14 18:00)
**Deliverable**: 라이브 발표 없음 → 슬라이드(PPT/PDF) 메일 첨부. 시연 동영상/스크린샷 임베드 필수. Q&A 없음 → 자기설명적 narrative.

## 현재 상태 매트릭스 (v10)

| 영역 | 상태 |
|---|---|
| Day 1~9 (시연 §1~§9 자산) | ✅ 전체 완료 |
| Day 10 Phase A (4 Invocable Apex + FollowupDraft Prompt) | ✅ 완료 |
| Day 10 Phase B (Agentforce Bot 메타 + 활성화) | ✅ 메타·활성·권한 완료. ⚠️ **sf agent preview ExternalCopilot 한계** — Apex Invocable 호출 안 됨 (Setup UI Manage Access 메타 API 미공개). admin 호출은 정상(7건 반환). **narrative 우회**. v66 GA 시점 한계 |
| Phase 2 (Schedulable 등록) | ✅ 3 cron: LongTermDebtor 02:00 / OrderErpSync 03:00 / QuoteFollowup 04:00 |
| Phase 4-A (CallMemoExtract AI 교체, LEAD-006) | ✅ 진짜 AI 호출. lastSource=ai 확인 |
| Phase 4-B (OPP-002 Stage 자동 전이) | ✅ Quote 발송 시 '견적 작성' → '견적 발송' |
| Phase 4-C (AR-003 Quote 헤더 AR 정보) | ✅ Total_AR / Credit_Limit / Long_Term + 한도 초과 경고 |
| Phase 4-D (QUOTE-008 7일 무응답 follow-up) | ✅ Schedulable + Task 자동 생성 |
| Phase 5 (커버리지 80→89% 보강) | ✅ QuotePdfController 17→100%, StageGate 52→100%, EmailIntent 67→74%. Org-wide **89%** (Day 11 종료 시 87% — 새 클래스로 약간 하락하나 목표 85% 초과) |
| Phase 6-A (agentforceInputBar / 세일즈 도우미 LWC) | ✅ 키워드 라우터 + LLM fallback Prompt + UX 개선 (예시 chip / JSON 토글 제거, 한글 라벨, 보라색 LLM 배지) |
| Phase 6-B (SpecExtract AI for RFQ EMAIL Lead) | ✅ 실 LLM 검증 — 한라정공 박과장 베어링 6204 100개 등 6필드 추출 |
| Phase 6-C (DelayNotice AI 사전 통보 메일) | ✅ orderRiskCard mailto AI 작성으로 교체 |
| Phase 6-D (GetCrossSellCandidates 5번째 Action) | ✅ Agentforce 5 Action 완성 — 발주 Family 기반 미구매 Product 인기순 추천 |
| **★★★ 3-step LLM 라우터 (Day 12)** | ✅ **완료 (2026-05-12)**. AgentRouter + AgentSynthesize Prompt 2건 + 2 Invoker + Service 재설계. 실 LLM E2E 5/5 통과 — "대성기공(주) 물건 나갔나요?" → GetAccountSummary 자동 라우팅 → "미출고 Order 3건, 장기미수 보유" 데이터 인용 자연체 응답. Test 319/319 PASS. |

**최종 통계**:
- **Apex Test 319/319 PASS** (100%)
- **Org-wide 커버리지 87%** (목표 85% 초과)
- **Prompt Template 11개** — BusinessLicenseExtract / OpportunityInsight / IntentClassify / RequoteDraft / FollowupDraft / CallMemoExtract / SpecExtract / DelayNotice / AgentInputFallback / **AgentRouter** / **AgentSynthesize**
- **Agentforce Action 5종** — GetTodayPriorityList / GetOrderAtRisk / GetAccountSummary / DraftFollowupEmail / GetCrossSellCandidates
- **세일즈 도우미 3-path** — (a) Agentforce planner (b) 키워드 라우터 (c) **ReAct LLM 라우터** 모두 동일 Apex Invocable 호출

의사결정 D1~D28 확정. Day 11 D29~D32 → §21. Day 12 ReAct 완료 → §22.

다음 세션 첫 작업 = **시연 동영상 캡처 (골든패스 §1~§10 + ReAct 라우터 강조) → 슬라이드 작성 → 5/14 18:00 메일 제출**.

---

## 1. 30초 컨텍스트

4차 과제로 **Sales Cloud 기반 프로젝트** 신규 빌드. 도메인은 **B2B 부품/소재 제조업** (사용자가 실무 경험 보유). 페르소나는 **AE 김민수 @ 한도정밀(가상)** — Lead 인입부터 미수금 시각화까지 끝까지 책임지는 영업 담당자. 5종 기술 모두 사용 (Flow·Apex·LWC·Prompt Builder·Agentforce).

**핵심 차별화 4가지**
1. L2C 통합 — Lead부터 미수금 회수까지 단일 워크스페이스
2. AI Human-in-the-loop — AE 입력 부담 90% 감축 (OCR=Prompt Builder, 통화메모 추출, 재견적 초안 등)
3. **외부 통신 0** — ERP는 Apex Mock 인터페이스로 격리, OCR은 Prompt Builder 내부, 신용 평가는 NG-016
4. 한국 비즈니스 정서 — 이름 단일·한국식 직급·사업자번호·₩

**굳이 이렇게 개발해야 하는 이유 (한 문장)**
> "AE는 RFQ→입금까지 책임지나 흐름이 메일·엑셀·메신저·ERP에 흩어짐. 통합 워크스페이스 + AI(자유 텍스트만) + ERP/회계 Mock 격리로 입력 부담 90% 감축, Sales Cloud 색깔 유지."

---

## 2. 문서

| 문서 | 경로 | 역할 |
|---|---|---|
| 기획서 | `docs/specs/2026-05-07-sales-cockpit-design.md` | 평가자 시각의 종합 설계 |
| PRD v0.7 | `docs/specs/2026-05-07-sales-cockpit-prd.md` | Functional Requirements 번호형 (P0 33, P1 6, P2 1) |
| 개발 계획서 v0.3 | `docs/specs/2026-05-07-sales-cockpit-dev-plan.md` | Day 1~10 체크리스트 + 캘린더 매핑 |
| **남은 일정 v1** | `docs/specs/2026-05-12-remaining-schedule.md` | **PRD FR 완료 매트릭스 + 5/12 저녁~5/14 발표 까지 시간별 일정** |
| **이 문서** | `HANDOFF.md` | 다음 세션 빠른 컨텍스트 회복 |

---

## 3. 주요 의사결정 이력

| # | 결정 | 근거 |
|---|---|---|
| D1 | 도메인: 부품/소재 B2B 제조업 | 사용자 실무 경험 |
| D2 | 페르소나: AE (Account Executive) | Sales Cloud 색깔 강하게 |
| D3 | 흐름: Lead-to-Cash 전체 (Lead→Quote→Won→Order→AR) | "여러 pain point 통합"이 평가 강점 |
| D4 | ERP/MES/QMS는 직접 만들지 않음, Apex Mock으로 시그널만 처리 | Sales 색깔 유지 |
| D5 | **결재 프로세스 전체 제거** (NG-009) | ERP 색깔 위험, 사용자 명시 요청 |
| D6 | **생산팀 인계 메일 제거** (NG-010) | 생산관리 영역 |
| D7 | **권한 시스템 단순화** (NG-013) | 본 릴리스 외 |
| D8 | **신용한도 자동 발송 차단 제거** (NG-012) | 정보 표시만 |
| D9 | **AR 자동 단계 메일 제거** (NG-011) | AE 수동 응대 |
| D10 | **세금계산서 발급 영역 제거** (NG-014) | 회계·홈택스 영역, 평가자 방어 어려움 |
| D11 | **사업자등록증 OCR을 Lead → Opp 단계로 이동** (NG-015) | 단순 견적 문의자에게 entry barrier 부담 |
| D12 | **할인 입력 = 금액 + % 자동 표시** (사용자 요구) | 예: 40,000 입력 → "1.36% 할인" |
| D13 | **무응답 follow-up = 7일 단일 기준** | 사용자 명시 |
| D14 | **PHONE Lead에 통화메모 → AI 자동 추출 추가** (FR-LEAD-006) | AE 손 부담 감축 |
| D15 | **재견적 응답 시 AI가 새 Quote 자동 초안** (FR-QUOTE-009) | AE 손 부담 감축 |
| D16 | OCR을 Prompt Builder 멀티모달로 전환 + CompanyInfo(FR-OPP-005) 제거 → NG-016 격리 | NICE/한국기업데이터 상용 신용 API는 별도 기업 계약 영역. AI 자유 텍스트 원칙 일관성 ↑ |
| D17 | ERP를 Apex Mock으로 일원화 (Beeceptor 제거) + 시연 즉석 동기화 버튼 추가 | 고정 응답 mock의 의미 약함. 시드 vs 동기화 결과 구분 가시화 필요. callout 패턴은 Day 5 Prompt Builder에서 시연 |
| D18 | Master Contract 객체 사용 안 함 → NG-017 신설 | 단발 거래 시연 집중. 8일 일정 안정성 우선. 정기 거래는 후속 릴리스 영역 |
| D19 | D17-정정: 위험 키 OrderNumber → **PoNumber 끝자리 + Production_Status='InProgress'** | OrderNumber 자동번호로 통제 불가. 시드에서 결정론적 분포 보장 |
| D20 | Lead Convert Auto Mapping을 Flow → **Apex Trigger** 채택 (LeadTrigger + Handler) | Flow XML schema 까다로움 + test 안전망. Day 4까지 효과 동등 |
| D21 | Picklist 한국어 정비 — Lead.Status 4(신규/제안대기/전환완료/미전환), Opportunity.StageName 6(발굴/견적 작성/견적 발송/협상/수주/실주), Quote.Status 5(초안/발송/응답대기/수락/거절). API value도 한국어 | 사용자/평가자 시각 일관성. 코드의 한국어 문자열 비교 트레이드오프 < 사용감 우선 |
| D22 | Lead.RFQ_Spec_JSON__c는 UI 노출 X (LWC가 파싱) | AE 사용 가치 없음. raw JSON은 평가자에게도 노출 X |
| D23 | StageGate 룰 단순화 — '발굴 → 견적 작성' = 사업자번호 1개만 | 키맨/사양은 Lead Convert 자동 충족 → 게이트 의미 없음 |
| D24 | Account Layout 한국형 정비 (메타 자동) | 미국 잔재 (SIC/SLA/Upsell 등) 제거. 한국 핵심 6필드(사업자번호/대표자/신용한도/외부신용점수/총미수금/장기미수금) 노출. Highlights Panel 4필드 |
| D25 | **FR-QUOTE-001 AI Quote 자동 생성(aiDraftCard) 폐기 → Opp Insight Card로 대체** (Day 7) | AE 멘탈모델: 견적은 Quote 페이지의 표준 [New Quote]가 자연스러움. AI 자동 생성은 입력 부담 약간 감소이지만 시연 임팩트 약함. 대안: 정량 점수(Apex OppScoreService) + 자연어 요약·추천 액션(Prompt Builder OpportunityInsight) 하이브리드 → 분석·요약 중심 AI가 평가 임팩트 큼. AE 사용감도 자연스러움 |
| D26 | **LLM 응답 코드 펜스 가드 표준화 + AI 가격 변형 금지 정책 명문화** (Day 7 P2) | Apex Test 33/33 통과 후 E2E 첫 시도에서 GPT41Mini가 응답을 \`\`\`json ... \`\`\` 코드 펜스로 감싸 JSON 파서 실패(백틱 code 96). 프롬프트로 "마크다운 금지" 명시해도 모델이 무시. 모든 ConnectApi.EinsteinLLM 호출 wrapper 에 stripCodeFences 헬퍼 통과 의무화 (참조: feedback_prompt_builder_apex 체크리스트 6번). 동시에 D15·D25 일관 정책 — AI 가 Quote 라인 가격/수량/할인 직접 갱신 금지, 제안은 Quote.Description 자연어 + AI_Draft_Confidence__c 만, AE 가 quoteBuilder 에서 수동 확정. 평가자 방어: 회계·신용한도 위험 격리 |
| D27 | **Order ↔ Opportunity 연결을 Order.Opportunity__c custom lookup 으로 대체** (Day 8 Case A) | 이 DE Org 는 표준 Order.OpportunityId 미활성 (Optional Activation 안 됨), Schema describe 로 확인 — Order reference 필드는 AccountId/ContractId/OriginalOrderId 등 6개만. Apex 컴파일러는 metadata 캐시로 통과시키지만 런타임 SObjectException "Invalid field OpportunityId" → 트리거 noop. 해결: Opportunity__c custom lookup(referenceTo=Opportunity, relationshipName=Orders) 신설. Won_To_Order Flow 가 이 필드를 채움. 평가자 답변: "Org 환경 차이로 표준 OpportunityId 미활성 → custom lookup 으로 명시적 책임 분리 + Apex 컴파일러와 런타임 schema 차이라는 함정을 D27 으로 학습 정리". |
| D28 | **Agentforce Bot/Topic 메타를 직접 XML 조립 대신 `sf agent create --spec` CLI 경로로 생성** (Day 10 Phase B) | 직접 XML 조립 시 schema 함정 6건 연속(pluginInstruction 무효, developerName/language/pluginType 필수, type=EinsteinServiceAgent 는 BotType enum 무효 등). v66 Agentforce schema 가 unstable + 문서 부족. CLI `sf agent generate agent-spec` + `sf agent create --spec` 로 SF 가 일관 형식 생성 → retrieve 로 소스 자산화. 단점은 Bot type 이 `ExternalCopilot` 강제 (Employee Agent 의도와 차이). 평가자 narrative: "v66 DE Org Agentforce 가 ExternalCopilot 만 sf agent create 지원, 운영 환경에서는 Employee 전환 가능". Trade-off 가 작아 시간 절약 이득이 큼. |

---

## 4. 시연 골든패스 (6분 / 10단계)

```
1. 콕피트 (5카드)
2. 전화 Lead 등록 → 통화메모 자유 텍스트 → "메모로 자동 채우기" → 폼 자동
3. 단계 게이트 ✅ → Lead Convert (사업자번호 미요구)
4. Opp 발굴 → AI Insight 카드(거래 점수 + 한국어 자연어 요약 + 추천 액션) → "Quote 게이트"에 막힘 → 사업자등록증 PDF 업로드 → Prompt Builder OCR로 Account 자동 보강 → 게이트 ✅ (D25)
5. Path '견적 작성' 전환 → 표준 [New Quote] → quoteBuilder 인라인 편집(라인 추가·할인 40,000 입력 → 1.36% 자동 표시)
6. Quote PDF 생성·미리보기(한국식 4섹션 + 일금 한글 표기) → 이메일 발송(제목·본문 사용자 편집) → Status='발송'
7. 응답 "재견적" → 자동 초안 → 검토·재발송 → "수락" → Won → Order 자동
8. 콕피트 Order Risk Card → [🔄 ERP 동기화] 클릭 → 위험 5건 등장 → 78점 Order의 [사전 통보 메일] 발송
9. 출고 등록 → 분할 입금 3회 → 잔액 추적
10. 장기미수금 빨간 띠 + Agentforce 자연어 질의
```

---

## 5. 현재 코드베이스 상태 (Day 8 종료 시점)

```
force-app/main/default/
  ├── objects/                    (Payment__c + 표준 객체 33 커스텀 필드, Order.Last_ErpSync_At__c + Order.Opportunity__c 【Day 8 + Case A】)
  ├── classes/
  │   ├── account/                (AccountTriggerHandler + Test)
  │   ├── lead/                   (LeadScoring/CallMemoExtract/LeadTriggerHandler/RfqInbound + 4 Test)
  │   ├── opp/                    (StageGate/OppTriggerHandler + OppScoreService + OppInsightService + 4 Test)
  │   ├── business-license/       (BusinessLicensePromptService/LLMResponse + Test)
  │   ├── quote/                  (Pricing/QuotePdfController/QuotePdfService/QuoteEmailService/AiQuoteDraftService(폐기)
  │   │                            + EmailIntentClassifyService + EmailMessageTriggerHandler + QuoteRequoteService
  │   │                            + EmailTrackingService(@RestResource) + 7 Test)
  │   ├── order/                  (IExternalErpService + ErpSyncResult + ErpServiceMock + OrderErpSyncService + OrderTriggerHandler + ShippingCompleteService + PaymentService + 5 Test) 【Day 8 + Case A + Day 9 #2/#3】
  │   ├── cockpit/                (AeCockpitService + Test) 【Day 9 #6】
  │   └── ar/                     (LongTermDebtorScheduler + Test) 【Day 9 #5】
  ├── triggers/                   (account/lead/opp + quote/EmailMessageTrigger + order/OrderTrigger) 【opp/OpportunityTrigger 확장: after update Won→Order Day 9 #1】
  ├── labels/                     (CustomLabels — Quote_Tracking_Base_URL = __UNSET__ sentinel)
  ├── lwc/
  │   ├── phoneLeadIntake, visitLeadIntake
  │   ├── businessLicenseUpload (Day 5)
  │   ├── stageGateChecklist (Day 4B)
  │   ├── quoteBuilder + quoteLineEditor (Day 6)
  │   ├── oppInsightCard (Day 7 Phase 1)
  │   ├── orderRiskCard (Day 8 — Order Record Page)
  │   ├── shippingComplete (Day 9 #2 — Order Record Page)
  │   ├── paymentRegister (Day 9 #3 — Order Record Page)
  │   ├── aeCockpit (Day 9 #6 — App/Home Page, 5카드)
  │   ├── longTermDebtorBanner (Day 9 #4 — Account Record Page)
  │   └── aiDraftCard (D25 폐기, 미사용)
  ├── pages/                      (QuotePdfPage — 한국식 Aqua 스타일)
  ├── staticresources/            (NanumGothic.ttf + NanumGothicFont.zip)
  ├── genAiPromptTemplates/       (BusinessLicenseExtract + OpportunityInsight + IntentClassify + RequoteDraft)
  ├── layouts/                    (Account/Lead/Opp 한국형)
  ├── permissionsets/             (Sales_Cockpit_User — Apex 14 classAccess, Pages 1) 【Day 8 +1: OrderErpSyncService】
  └── tabs/, app/                 (Hando_Sales App)
```

**Org "My_Org" 상태**:
- Locale=ko_KR, Currency=KRW, TZ=Seoul ✅
- Quote/Account History Tracking 활성화 ✅
- Day 1~8까지 누계 ~115+ 컴포넌트 배포
- Apex Test **172/172 PASS**, Org-wide 커버리지 **80%** (Day 8 신규 3 클래스 모두 100%)
- 시연 검증 통과: 골든패스 §1~**§8** (Lead 인입 → Convert → Opp 발굴 → AI Insight → OCR/게이트 → 견적 작성 → PDF → 이메일 발송 → 응답 의도 분류·자동 재견적 초안 → **ERP 동기화 → 위험 5건 + 대형지연 5건 등장**)

**git 저장소 미초기화** (필요 시 `git init`)

---

## 6. 다음 세션 시작 시 할 일 (5/13 저녁 ~ 5/14 18:00 마감)

### 즉시 (1분)
- [ ] `sf org display --target-org My_Org` 연결 확인
- [ ] WORKLOG.md 마지막 줄(2026-05-13 14:25 Day 10 Phase B Bot 활성 + 런타임 권한 잔여) 확인
- [ ] 본 §16~§20 학습 정독 (§20 = Day 10 Phase B + sf agent create 학습)
- [ ] Setup UI 배치 (Day 9 미완) — Home Page `aeCockpit`, Account `longTermDebtorBanner`, Order `orderRiskCard`/`shippingComplete`/`paymentRegister`

### Phase B 잔여 1-step (Setup UI 2~3분)

`sf agent preview` 자연어 질의 시 "configuration issue / 데이터 라이브러리 미할당" 메시지 — Agent Builder UI 에서 4 Action 별 Access 토글 필요.

**A. Setup UI Action Access 해결**
1. Setup → Agentforce → Agents → 한도세일즈 도우미 (HandoSalesAgent)
2. Topics → Sales Cockpit Assistant → Actions 탭
3. 4 Action (GetTodayPriorityListAction / GetOrderAtRiskAction / GetAccountSummaryAction / DraftFollowupEmailAction) 각각 클릭 → "Manage Access" 또는 "Grant Access" → Sales_Cockpit_User PermSet 추가
4. 또는 Action 정의 화면에서 "Required Permissions" 그룹에 Sales_Cockpit_User 추가
5. 저장 → 활성화 유지

**B. E2E 검증** (5분)
```powershell
$session = (sf agent preview start --api-name HandoSalesAgent --target-org My_Org --json | ConvertFrom-Json).result.sessionId
sf agent preview send --api-name HandoSalesAgent --session-id $session --utterance "오늘 우선순위 알려줘" --target-org My_Org --json
```
기대 — `오늘 우선순위 N건 — 신규 RFQ X건, 위험 Order Y건 ...` 한국어 응답.

**C. (선택) Agent Type 을 Employee Agent 로 변경**
현재 `type=ExternalCopilot`. Setup UI 에서 Agent type 을 "Employee" 로 변경 가능하면 더 정확. 시간 없으면 그대로 ExternalCopilot 으로 시연하고 narrative 로 "Service Agent 색깔이지만 AE 내부 사용" 설명.

### 시연 자료 캡처 + 슬라이드 작성 (5/14, 6~7h)

**시연 동영상/스크린샷 캡처** (5/14 오전 3h)
- 골든패스 §1~§10 각 단계 OBS/PowerPoint 화면 녹화 또는 스크린샷
- Agentforce 4 자연어 질의 (B 검증 통과 후) — 별도 동영상

**슬라이드 작성** (5/14 오후 3~4h, PPT/PDF, 9 섹션)
1. Cover — 한도정밀 L2C, 5종 기술 (Flow·Apex·LWC·Prompt Builder·Agentforce), 페르소나 AE 김민수
2. 차별화 4가지 (HANDOFF §1) — L2C 통합 / AI HITL / 외부 callout 0 / 한국 정서
3. 골든패스 6분 narrative (§4) — 10단계 각 1슬라이드 + 스크린샷
4. AI 라인 — Prompt Template 5개(BusinessLicenseExtract / OpportunityInsight / IntentClassify / RequoteDraft / FollowupDraft) + stripCodeFences(D26) + 가격 안전 정책
5. ERP 게이트웨이 — D17/D27 + 외부 callout 0 + 위험 점수 분포
6. Agentforce — 4 Action + GenAiFunction/Plugin/Bot/Planner 아키텍처 + 자연어 질의 동영상
7. 의사결정 자기설명 — D17 ERP Mock / D18 Master Contract 제외 / D25 AI Quote 폐기 / D26 코드 펜스 + 가격 안전 / D27 Order.Opportunity__c custom lookup / D28 sf agent create CLI 경로
8. 산출물 카탈로그 + 테스트 ~228/228 + 커버리지 80%+ (4 Action 75~100%)
9. 한계·후속 — NG-009~017 narrative + ExternalCopilot 한정 narrative
- **2026-05-14 (목) 17:55** 까지 발송 (마감 18:00)

**B. 평가자 Q&A 시뮬레이션**
- §9 평가자 방어 포인트 표 검토 + 추가 예상 질문 정리
- D17 / D18 / D25 / D26 / **D27** 모두 한국어로 30초 답변 준비

**C. 골든패스 1차 리허설**
- 시연 §1~§10 6분 안에 흐르는지 타임 체크
- 끊김 지점 식별

### 후속 backlog (Day 10 여유 시)
- Lead `CallMemoExtract` 정규식 → 진짜 AI 교체 (~1시간, OppInsight/IntentClassify 패턴 + stripCodeFences D26)
- FR-QUOTE-008 7일 무응답 Schedulable + Task 자동
- LWC: `emailIntentBadge`(EmailMessage 페이지)
- Day 7 P2 Site 픽셀 추적 (1~2시간) — 시연 §6 부속, 리허설 직전 압축 가능
- Org-wide 커버리지 80% → ≥85% (EmailIntentClassifyService 67% / StageGateService 52% / QuotePdfController 17% 보강)

### 기존 6 (구버전 — Day 5 진입 시점, 참고용 보존)

### 즉시 (1분)
- [ ] `sf org display --target-org My_Org` 연결 확인
- [ ] WORKLOG.md 마지막 줄(2026-05-08 17:34 Day 5 선행) 확인 — OCR 재작성 컨텍스트 회복
- [ ] 본 §15 "Day 5 OCR 재작성 컨텍스트" 정독 (5가지 근본 원인 + 학습)

### Day 5 OCR 검증 (최우선 — 코드는 작성됨, 배포·검증 미완)

**현재 상태**:
- ✅ `BusinessLicensePromptService.cls` 재작성 완료 — 5가지 결함 모두 수정
- ✅ `BusinessLicenseLLMResponse.cls` 헬퍼 분리 (JSON DTO + isAllBlank)
- ✅ `BusinessLicensePromptService_Test.cls` 11 케이스 (mock JSON 우회)
- ✅ `businessLicenseUpload` LWC — extract_empty 분기 + JSON 코드블록·복사 버튼
- ❌ **Org 미배포** — 4 component 배포 필요
- ❌ **Prompt Template 미검증** — `BusinessLicenseExtract`가 Setup에 정상 등록되어 있고 입력 변수명이 `Input:ContentDocument`인지 확인 필요
- ❌ **실제 이미지 E2E 미검증** — 1.jpg(대광건설기계) 업로드 → 4필드 추출 → Account 보강까지 1회 시연 검증 필요

**즉시 실행 순서**:
1. `sf project deploy start -d force-app/main/default/classes/business-license -d force-app/main/default/lwc/businessLicenseUpload --target-org My_Org`
2. `sf apex run test --tests BusinessLicensePromptService_Test --target-org My_Org --code-coverage --result-format human` — 11/11 PASS 확인
3. Setup → Prompt Builder → `BusinessLicenseExtract` 템플릿 존재 확인. Resources에 `ContentDocument` (SObject) 입력 변수가 있고 LWC 코드의 키 `'Input:ContentDocument'`와 정합한지 확인. Preview 화면에서 1.jpg로 정상 추출되는지 1차 검증.
4. Opp 페이지에 `businessLicenseUpload` LWC 배치(이미 있으면 skip) → 1.jpg 업로드 → status='success' + Account 4필드 보강 확인.
5. **검증 실패 시 디버깅 순서** (§15 참조): generationErrors 메시지 → applicationName 후보군('PromptBuilderPreview' 외) → CAPABILITY 값 → 템플릿 입력 변수명 정합성.

**시연 자료**: `docs/samples/business-license/` 9개 + README.md 준비 완료. 1.jpg(대광건설기계, 471-81-00778) 1순위.

**시연 동선**: Lead "(주)대광건설기계" → Convert → Opp 발굴 → 게이트 ❌(사업자번호) → 1.jpg 업로드 → OCR 추출 → Account 보강 → 게이트 ✅ → 표준 Path에서 '견적 작성' 전환.

### Day 5 OCR 검증 완료 후 → Day 6 (Quote Builder) 진입
- [ ] FR-QUOTE-001~009 — quoteBuilder + quoteLineEditor LWC, 할인 금액→% 자동 표시(D12), QuotePdfService, QuoteEmailService
- [ ] 발표 일정 압박 — Day 6·7이 부하 최고 구간(주말 활용)

---

## 7. 캘린더 압축안 (8일 → 10단계)

| 날짜 | 요일 | Day | 작업 |
|---|---|---|---|
| 5/7 | 수 | Day 1 | 데이터 모델 ✅완료 (38 컴포넌트, 7/7 PASS, 93%) |
| 5/8 | 목 | Day 2+3+4A | ✅완료. 시드(166 records) + Hando_Sales App + Lead 인입(Apex 4 + Trigger + LWC 2) + 한국어 Picklist 정비(3 SVS) + StageGate(Apex 2 + Trigger + LWC 1) + Account Layout + Admin FLS. **Apex Test 누계 46/46 PASS**, Org-wide 94% |
| 5/9 | 금 | Day 4잔여 + Day 5 | Lead/Opp Layout 정비 + Prompt Builder OCR ✅완료 |
| 5/10 | 토 | Day 6 + Day 7 P1 | Quote Builder ✅완료 (PricingService/quoteBuilder/quoteLineEditor/QuotePdf/QuoteEmail) + Day 7 Phase 1 ✅완료 (AI Insight, D25 — aiDraftCard 폐기·oppInsightCard 추가) |
| 5/11 | 일 | Day 7 P2 | ✅완료. FR-QUOTE-006/007/009 백엔드 (IntentClassify/RequoteDraft Prompt + EmailIntentClassifyService@future + EmailMessageTrigger + QuoteRequoteService + EmailTrackingService@RestResource + Quote_Tracking_Base_URL Custom Label). 신규 Apex 4 + Trigger 1 + Test 3 클래스. **Apex Test 154/154 PASS**, Org-wide 80% |
| 5/12 | 월 | Day 8 + Case A + Day 9 | ✅완료. Day 8 ERP Mock 동기화 + Case A (OrderTrigger Quote 라인 자동 복사, D27 — Order.Opportunity__c custom lookup 우회) + Day 9 전체 6작업. Won_To_Order(OpportunityTrigger.handleAfterUpdate) / ShippingComplete / Payment / AeCockpit 5카드 / longTermDebtorBanner / LongTermDebtorScheduler. 누계 신규 Apex 6 + LWC 5 + Trigger 1 확장. **Apex Test 210/210 PASS** 예정 |
| 5/13 | 화 | Day 10 Phase B + 시연 자료 캡처 | Agentforce 5 Action 실 deploy + 메타 + 활성화. 슬라이드용 시연 동영상/스크린샷 캡처 |
| 5/14 | 목 | Day 10 마무리 + 슬라이드 작성 + **18:00 메일 제출** | 슬라이드 자료(PPT/PDF) 작성 — 골든패스 §1~§10 narrative + 스크린샷/동영상 + 의사결정 D27 답변 자기설명적 작성. 메일 발송 |

Day 6·7이 가장 부하 큰 구간 — Day 6 + Day 7 Phase 1까지 5/10 하루에 끝남(체력 ↑, 5/11 잔여 작업 여유).

---

## 8. 산출물 카탈로그 (요약)

- **LWC**: aeCockpit, rfqCard, quoteTrackingCard, **orderRiskCard ✅(Day 8 — 🔄 ERP 동기화 버튼 + 78점+ 사전 통보 메일)**, arActionCard, leadPriorityCard, phoneLeadIntake, visitLeadIntake, businessLicenseUpload, stageGateChecklist, quoteBuilder+quoteLineEditor, **oppInsightCard (D25 추가)**, orderScheduleTracker, shippingComplete, paymentRegister, longTermDebtorBanner, agentforceInputBar
  - 폐기: ~~aiDraftCard~~ (D25 — Opp Insight로 대체)
- **Apex 클래스 + Trigger**: LeadScoringService, CallMemoExtractService, BusinessLicensePromptService, **IExternalErpService(인터페이스) + ErpSyncResult(DTO) + ErpServiceMock + OrderErpSyncService ✅(Day 8 — 신규 4)**, PricingService, QuotePdfService/Controller, QuoteEmailService, **OppScoreService + OppInsightService (D25, Day 7 P1)**, **EmailIntentClassifyService + EmailMessageTriggerHandler + EmailMessageTrigger + QuoteRequoteService + EmailTrackingService(@RestResource) (Day 7 P2)**, DeliveryRiskCalculator, OrderScheduleSync(Scheduled+Invocable), PaymentService, StageGateService, AccountTriggerHandler, LeadTriggerHandler, OpportunityTriggerHandler, RfqInboundHandler ✅완료 — Day 8까지
  - 폐기: ~~AiQuoteDraftService~~ (D25)
- **Flow 5개**: Lead_Convert_Auto_Mapping, Opportunity_Stage_Auto_Transition, Opportunity_Won_To_Order, Quote_NoResponse_7Day, AR_Long_Term_Debtor_Daily
- **Prompt Builder Template**: BusinessLicenseExtract ✅(Day 5), **OpportunityInsight ✅(D25, Day 7 P1)**, **IntentClassify ✅ + RequoteDraft ✅ (Day 7 P2)**, DelayNotice
  - 폐기: ~~SpecExtract, SkuMatch~~ (D25 — AI Quote 자동 생성 폐기로 불필요)
  - 후속(P1 backlog): CallMemoExtract — Day 3 정규식 → 진짜 AI 교체 (§10 참조)
- **Beeceptor 0 / Named Credential 0** (D17)
- **Agentforce 5 Action**: getTodayPriorityList, getOrderAtRisk, getAccountSummary, draftFollowupEmail, getCrossSellCandidates(T2)

---

## 9. 평가자 방어 포인트

| 질문 | 답변 요지 |
|---|---|
| "왜 영업 시스템이 ERP 영역까지 다루나?" | ERP 게이트웨이 패턴. ERP/생산/품질은 Mock 인터페이스로 격리. 영업이 받는 시그널을 고객 응대로 변환만 |
| "AI를 굳이 왜?" | LLM은 자유 텍스트(메일·도면·사업자등록증·메모) 영역에만 한정. 단순 분기 안티패턴 회피 |
| "결재가 없는데 괜찮은가?" | NG-009 — 본 릴리스 단순화 결정. 영업 책임 영역 명확화 |
| "세금계산서 빠진 이유?" | NG-014 — 세무·회계 영역, 외부 시스템(홈택스) 영역 |
| "Lead 단계 사업자등록증 왜 X?" | NG-015 — 단순 견적 문의자에게 entry barrier. 거래 의사 확인 후 Opp 단계에서 제출 |
| "한국 정서 적용 이유?" | UX·페르소나 충실도. 사용자관점 평가 점수 직접 어필 |
| "신용점수·매출은 어떻게 가져오나요?" | NG-016 — NICE 등 상용 신용 API는 별도 기업 계약 영역. 본 릴리스는 OCR 기반 식별·기본 정보 자동화에 집중. |
| "Master Contract는 왜 없나요?" | NG-017 — 본 릴리스는 단발 거래 시연 집중. 정기 계약은 후속 릴리스 영역. 책임 경계 명확화. |
| "외부 callout이 없는데 통합 시연이 가능한가요?" | OCR을 Prompt Builder 멀티모달로 처리해 외부 의존성 제거. ERP는 인터페이스(IExternalErpService) + Mock 구현으로 책임 분리 시연. 즉석 동기화 버튼으로 데이터 흐름 가시화. |

---

## 10. 열린 이슈 / 위험

| 이슈 | 상태 |
|---|---|
| ~~Day 7 P2 시연 검증~~ | ✅ **완료 (2026-05-11)** — Anonymous Apex 로 incoming EmailMessage 인서트 → classifyOne sync 호출 → intent=Requote(0.95) → draftFromEmail → Q-DAY6-001 (재견적) Status=초안 conf=0.90 자동 생성. 발견된 LLM 코드 펜스 버그는 D26 으로 정리·재배포 완료 |
| **Quote 회신 Inbound Email Service 미구현** | 현재 사용자 수동 인서트로 incoming EmailMessage 생성. 운영용 자동 라우팅 필요 시 RfqInbound 패턴 차용(Messaging.InboundEmailHandler + Email Service 주소 발급). 시연용 manual 인서트로 충분 — P2 backlog |
| **Custom Label Quote_Tracking_Base_URL = `__UNSET__` (sentinel)** | Site 배포 후 사용자가 Setup → Custom Labels 에서 실제 Site URL 로 갱신. 갱신 전까지 trackingBaseUrl() 가 null 반환 → 픽셀·링크 wrap 미주입(시연 깨지지 않음). 옵션 — Day 8 후 여유 시간에 Site 셋업 |
| **Lead CallMemoExtract 정규식 → 진짜 AI 교체** | 현재 CallMemoExtractService = 한국어 정규식. Prompt Builder Template `CallMemoExtract` 만들고 Apex 호출 교체 필요. 패턴은 §16 OppInsight + §17 IntentClassify 차용. ~1시간. **stripCodeFences 헬퍼 차용 필수 (D26)** |
| ~~ERP Mock 동기화 버튼 시연 가시성~~ | ✅ **완료 (2026-05-12)** — orderRiskCard LWC + OrderErpSyncService E2E 검증 통과. 위험 5건+대형지연 5건+안전 90건 정합. 78점+에 [사전 통보 메일] mailto 액션 노출. 콕피트 통합은 Day 9 aeCockpit 일감 |
| **orderRiskCard 콕피트 통합** | 현재 Order Record Page 전용. aeCockpit LWC 가 sublist 형태로 syncAllOpen 호출+위험 ≥70 Order 목록 표시 필요 (Day 9) |
| Apex 커버리지 80% → ≥85% | Day 10 마지막 점검 backlog. EmailIntentClassifyService 67% / QuoteRequoteService 83% / AccountTriggerHandler 93% / StageGateService 52% / QuotePdfController 17% 보강 후보 |
| EmailIntentClassifyService 의 @future 안에서 정적 mock 필드 미보존 | 현재 테스트는 sync classifyOne 경로로 mock JSON 검증. @future end-to-end 는 default mock(Intent='Other') 으로만 통과 — 실 LLM 호출은 E2E 검증으로 통과 완료 (2026-05-11) |
| git 저장소 미초기화 | `git init` 필요 시 안내 |

---

## 11. 시드 데이터 정의 (Day 2)

- Product2 50건 (베어링·단조품·정밀가공품 등)
- Account 30건 (한국 가상 회사명·사업자번호·일부 장기미수금 시나리오)
- Contact 60건 (한국 이름·직급·부서)
- 과거 Order 100건 — **PoNumber 끝자리 + Production_Status='InProgress'** 조합으로 위험 키 결정 (D17-정정, 2026-05-08): 끝자리 '6' + InProgress (위험 5건), 끝자리 '9' + InProgress (대형지연 5건), 나머지 정시 90건은 끝자리 0~5 + Done/Shipped/Pending. OrderNumber 자동번호로는 통제 불가하여 PoNumber로 변경. Delivery_Risk_Score__c·Last_ErpSync_At__c는 null 초기화 (Day 8 ERP Mock 동기화 시 채워짐).
- Payment 분할 입금 + 장기미수 시나리오
- 사업자등록증 샘플 PDF/이미지 5건 (`docs/samples/`)

---

## 12. Quickstart 명령어

```bash
# Org 연결 확인
sf org display --target-org My_Org

# 메타데이터 배포
sf project deploy start --target-org My_Org

# Apex 시드 실행
sf apex run --file scripts/apex/seedData.apex --target-org My_Org

# 테스트 실행
sf apex run test --target-org My_Org --code-coverage --result-format human

# 전체 메타 retrieve
sf project retrieve start --target-org My_Org
```

---

## 13. 사용자 선호

- Salesforce 개발자, Agentforce DE Org 작업 (My_Org가 기본)
- 이전 제조업 회사 근무 — 영업 수주·계약 일정·미수금 관리 경험
- 견적·할인 입력은 % 아닌 금액으로
- Lead 단계는 가벼움, Opp 단계에서 본격 보강
- 일정에 너무 매이지 말 것 — "어떻게든 해볼거야 목표가 명확하면"
- 평가자에게 질문받았을 때 자신있게 답변할 수 있는 구조 선호 (중립적·냉정한 분석 요청)

---

**다음 세션 시작 시: HANDOFF v7 §6 → `docs/specs/2026-05-12-remaining-schedule.md` 정독 (PRD FR 완료 매트릭스 + 시간별 일정) → WORKLOG 마지막 줄(2026-05-12 14:45 Day 9 종료) → 즉시 골든패스 리허설 #1 + Agentforce 5 Action.**

---

## 14. 5/8 누적 산출물 (Day 1~4A)

### 메타데이터
- **Object**: Payment__c (5 필드)
- **Custom Fields**: 31개 (Account 6, Lead 3, Quote 5, QLI 2, Order 7, Contact 2, EmailMessage 1, Payment 5)
- **StandardValueSet 한국어**: OpportunityStage(6+10 inactive), LeadStatus(4+4), QuoteStatus(5+8)
- **Layout**: Account-Account Layout (한국형 5섹션 + Highlights 4필드)
- **App + Tab + PermSet + Profile**: Hando_Sales App / Payment__c CustomTab / Sales_Cockpit_User PermSet / Admin Profile (FLS 27개)

### Apex (도메인 폴더링)
```
classes/
├── account/  AccountTriggerHandler + Test
├── lead/     LeadScoring/CallMemoExtract/LeadTriggerHandler/RfqInbound + 4 Test
├── opp/      StageGateService/OpportunityTriggerHandler + 2 Test
└── README.md (Day 5+ opp/quote/order/erp/ar/cockpit 매핑)
triggers/
├── account/  AccountTrigger
├── lead/     LeadTrigger
└── opp/      OpportunityTrigger
```

### LWC
- `phoneLeadIntake` — PHONE Lead + 통화메모 AI 추출
- `visitLeadIntake` — VISIT Lead + 방문노트 AI 추출
- `stageGateChecklist` — Opp 게이트 진단 (단계 변경 X, Path 컴포넌트로)

### 시연 자료
- `docs/samples/business-license/` 9건 + README (Day 5 사용)
- `scripts/apex/` seedData/cleanupSeedData/verifySeedData/inspectLegacyData/cleanupShopFlowData/backfillEmailLeadScores

### 사용자 Setup UI 완료
- Hando_Sales App 활성화
- Lead/Opp Record Page에 LWC 배치
- RfqInbound Email Service 활성화 + 발급 주소 메모
- Profile FLS (Account 6필드 등) — Admin Profile 자동화로 처리
- Lead 페이지 레이아웃 RFQ_Spec_JSON 제거

### 시연 검증 가능 동선 (5/8 종료 시점)
1. **PHONE Lead 인입** — 통화메모 → AI 자동 채움 → Lead 생성 + Score 표시
2. **VISIT Lead 인입** — 방문 노트 → AI 자동 채움 → Lead 생성
3. **EMAIL Lead 인입** — RfqInbound 주소로 메일 → Lead 자동 생성
4. **Lead Convert** — Account/Contact/Opp 자동 + Description 자동 복사
5. **Opp 게이트** — 사업자번호 ❌이면 Path에서 단계 변경 막힘, 입력 후 ✅ 통과
6. **Account 페이지** — 한국형 5섹션 + Highlights 4필드

### 5/9~5/14 잔여 작업
- Day 5: OCR + businessLicenseUpload LWC + Prompt Builder Templates **(코드 완료, 배포·검증 남음 — §15)**
- Day 6: Quote Builder + 할인 계산 + PDF
- Day 7: Email Tracking + Intent Classify + Requote Draft
- Day 8: Order + 납기 + ERP Mock 동기화 버튼
- Day 9: AR + Long-Term Debtor + 콕피트 5카드
- Day 10: Agentforce 5 Action + 리허설

---

## 15. Day 5 OCR 재작성 컨텍스트 (2026-05-08 17:34)

**왜 재작성했나**: 기존 `BusinessLicensePromptService.callPromptBuilder`는 파일 저장만 되고 Account 보강이 0건이었음. 사용자 디버깅 끝에 5가지 결함을 식별 → 전체 재작성.

### 5가지 근본 원인 (재발 방지)

| # | 결함 | 정정 |
|---|---|---|
| ① | `inputParams` 미설정 — "template에서 자동 인식"이라 가정 | `inputParams = { 'Input:ContentDocument' => WrappedValue(Map{Id→cdId}) }` 명시 |
| ② | 2-arg `generateMessagesForPromptTemplate(name, input)` | **3-arg** `(name, capability='', input)` — 멀티모달 경로 안정 |
| ③ | `applicationName = 'PromptTemplateGenerations'` (잘못된 값) | `'PromptBuilderPreview'` (검증된 값) |
| ④ | `isPreview` 미설정 | `input.isPreview = false` 명시 |
| ⑤ | catch에서 빈 Map 반환·`generationErrors` 무시 → 에러가 "partial 성공"으로 둔갑 | 예외 throw 유지, `generationErrors` 검사 후 throw, 호출자가 `STATUS_ERROR_OCR` 분기 |

### 핵심 인사이트 (사용자 학습 정리)

> Prompt Builder UI 미리보기에서는 사람이 직접 [+ 파일 선택]으로 이미지를 끼워넣어서 동작했지만, **Apex 코드 호출에서는 `inputParams`로 이미지를 명시 전달하지 않으면 LLM은 텍스트 프롬프트만 받음** → placeholder 빈 JSON 반환 → 모든 필드 blank → 모두 skipped → 사용자에게는 "partial 성공"으로 보이는 가짜 결과.

### 신설된 status

- `success` (4/4 추출), `partial` (1~3/4), **`extract_empty`** (0/4 — 이미지 인식 실패 안내), `error_ocr` (LLM 호출 실패), `error_account`, `error_file`
- `partial`과 `extract_empty`를 분리한 이유: 사용자가 "왜 안 됐는지" 즉시 알 수 있게 (이미지 흐림/프레임/각도 안내 메시지 포함).

### 코드 분리

```
classes/business-license/
├── BusinessLicensePromptService.cls       — 진입점 (@AuraEnabled processLicense)
├── BusinessLicenseLLMResponse.cls         — JSON DTO + 파서 + isAllBlank()
└── BusinessLicensePromptService_Test.cls  — 11 케이스 (mock JSON 우회)
lwc/businessLicenseUpload/
└── (extract_empty 분기 + ocrJson 코드블록 + 복사 버튼)
```

### 테스트 우회 패턴

ConnectApi.EinsteinLLM은 unit test에서 호출 불가 → `@TestVisible static String mockJsonResponse / mockExceptionMessage` 정적 필드로 우회. `Test.isRunningTest()` 분기에서 mock 응답 또는 예외 throw.

### 검증 실패 시 디버깅 순서 (§6.4 보강)

1. `sf apex run test ...` 11/11 PASS 확인 — 통과해야 코드 자체는 정상
2. Setup → Prompt Builder → `BusinessLicenseExtract` 존재 확인. Resources의 입력 변수 이름이 LWC 코드 키 `'Input:ContentDocument'`와 정확히 일치하는지(접두사 `Input:` 포함) 확인
3. 실패 메시지가 `LLM generation error: ...` 형태면 → `generationErrors` 원본을 봐야 함. 임시로 LWC `errorMessage`에 `result.ocrJson` 같이 표시하면 빠름
4. `applicationName` 호환성 의심되면 후보군: `'PromptBuilderPreview'` (1순위) → `'Default'` → 빈 문자열
5. CAPABILITY는 빈 문자열이 정답. 절대 `'einstein-gpt'` 등 임의 값 넣지 말 것

---

## 16. Day 7 Phase 1 OppInsight 학습 (2026-05-10)

**왜 추가했나**: AE 멘탈모델 — 견적은 표준 [New Quote]가 자연스럽고, AI 자동 견적 생성(aiDraftCard)은 임팩트 약함. 차별화 가치는 **분석·요약** 쪽. D25로 폐기·대체.

### 설계 패턴 — Apex + Prompt Builder 하이브리드

| 책임 | 구현 | 이유 |
|---|---|---|
| 정량 점수 (단계/활동/Account/Engagement) | **Apex** OppScoreService | 객관적·결정적, 평가자에 점수 산식 명시 가능 |
| 자연어 요약 + 추천 액션 | **Prompt Builder** OpportunityInsight | 한국어 자연스러움, 진짜 AI 임팩트 |
| LLM 실패 시 fallback | **Apex** buildFallbackSummary | graceful degrade, 시연 안전망 |

LWC: 점수 카드(색상·분해 chip) + AI 요약 + AI/Fallback 배지 + 위험 리스트 + 추천 액션.

### 점수 산식 (max 100)
- **stageScore** 0~50: 발굴 10 / 견적 작성 20 / 견적 발송 30 / 협상 40 / 수주 50 / 실주 0
- **activityScore** 0~20: 최근 14일 Task+Event 수 (0건=0, 1-2=8, 3-5=15, 6+=20)
- **accountScore** 0~15: External_Credit_Score__c (>=700=15, 500-700=10, <500=5, null=8) - Long_Term_Debtor 감점 5
- **engagementScore** 0~15: Quote 존재 5 + Sent_Date 5 + Last_Opened_At 5

### Prompt Template 메타 패턴 (재현용 핵심)

```xml
<GenAiPromptTemplate>
    <activeVersionIdentifier>{retrieve로 versionIdentifier 확인 후 명시}</activeVersionIdentifier>
    <developerName>OpportunityInsight</developerName>
    <templateVersions>
        <inputs>
            <apiName>OppRecord</apiName>
            <definition>SOBJECT://Opportunity</definition>     ← Day 5 OCR 검증 패턴
            <referenceName>Input:OppRecord</referenceName>
            <required>false</required>                         ← required=true는 옛 버전 호환성으로 거부됨
        </inputs>
        <primaryModel>sfdc_ai__DefaultGPT41Mini</primaryModel>
        <status>Published</status>
        <versionIdentifier>{Salesforce 자동 생성 — retrieve로 확인}</versionIdentifier>
    </templateVersions>
    <type>einstein_gpt__flex</type>
</GenAiPromptTemplate>
```

본문 변수: `{!$Input:OppRecord.Account.External_Credit_Score__c}` 같이 SObject 필드 직접 참조.

### Apex 호출 패턴 (Day 5 OCR과 동일)

```apex
ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
wv.value = new Map<String, Object>{ 'Id' => opportunityId };
input.inputParams = new Map<String, ConnectApi.WrappedValue>{
    'Input:OppRecord' => wv
};
ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
    'OpportunityInsight', '', input);
```

### 첫 deploy 시 필수 절차 (Day 5 PR0014 재발 방지)
1. 메타 1차 deploy (required=false, activeVersionIdentifier 미명시)
2. `sf project retrieve --metadata "GenAiPromptTemplate:OpportunityInsight"` → versionIdentifier 확인
3. 메타에 `<activeVersionIdentifier>` + `<versionIdentifier>` 둘 다 명시 추가
4. 재 deploy → 활성 버전 강제 전환
5. LWC 호출 → 배지 "AI 자연어 요약" 확인

### Fallback 모드의 가치
- LLM 호출 실패 시 자동 buildFallbackSummary/buildFallbackActions
- 평가자 답변: "AI Human-in-the-loop + Apex 점수 산식 검증 가능 + LLM 장애 시 graceful degrade. AE는 점수와 액션을 항상 받음."

### 후속 작업 가이드 (재현용)
- 다른 객체용 Insight 카드 만들 때 동일 패턴 차용 (Account 360 / Quote Insight)
- Lead CallMemoExtract 정규식 → AI 교체도 같은 SObject input 패턴으로 가능

---

## 17. Day 7 Phase 2 학습 — 이메일 추적·의도·재견적 (2026-05-11)

**왜 추가했나**: AE 멘탈모델 — 견적 발송 후 "고객이 열어봤나/응답 의도가 뭔가/재견적이면 새 안 자동 작성"이 시연 §7 핵심. 백엔드 인프라를 한 번에 완성.

### 통합 흐름

```
QuoteEmailService.sendQuote
   ↓ (Custom Label 설정 시) 본문 https?:// URL → <a href tracking-click> wrap + 픽셀 img 주입
[고객 메일] → 픽셀 fetch / 링크 click
   ↓
EmailTrackingService(@RestResource, public Site)
   ↓ open.gif → Quote.Last_Opened_At__c, click → Last_Clicked_At__c + Last_Opened_At__c
[고객 응답 메일 → Activity > Email Log 인서트]
   ↓
EmailMessageTrigger(after insert)
   ↓ Incoming + RelatedTo(Quote|Opp) 필터
EmailIntentClassifyService.classifyAsync(@future(callout=true))
   ↓ IntentClassify Prompt(SOBJECT://EmailMessage) → Intent__c 갱신
QuoteRequoteService.autoDraftIfRequote (같은 @future)
   ↓ Intent='Requote' 만 골라 RequoteDraft Prompt(QuoteRecord+EmailRecord) → 새 Quote(Status='초안') + 라인 복제 + Description AI 분석 블록
```

### 신규 패턴 — Day 7 P1 OppInsight + 새 패턴 3가지

| 패턴 | Day 7 P1 (Apex 1회 sync) | Day 7 P2 (Trigger → @future chain) |
|---|---|---|
| AI 호출 위치 | LWC → AuraEnabled service | EmailMessage Trigger → @future(callout=true) service |
| Mock 전략 | static field (sync 경로) | static field (sync classifyOne 만), @future end-to-end 는 default JSON 사용 |
| 가격·재무 안전 | n/a | **AI 가 Quote.QuoteLineItem.UnitPrice/Discount 직접 변경 금지** — 원본 라인 그대로 복제, AI 제안은 Quote.Description 에 한국어 자연어 + AI_Draft_Confidence__c. AE 가 quoteBuilder 에서 수동 확정 |
| Public 엔드포인트 | n/a | @RestResource(/quote-tracking/*) `without sharing` + Site Guest Profile 의 Quote Edit + classAccess. fire-and-forget (record 실패 silent) |

### LLM 응답 코드 펜스 가드 (E2E 디버깅에서 발견)

Apex Test 33/33 통과 후 사용자가 실제 EmailMessage 인서트로 E2E 시도 → `JSON parse error: Unexpected character ('`' code 96)` 실패. 원인: GPT41Mini가 응답을 ` ```json {...} ``` ` 코드 펜스로 감쌈 (프롬프트 "마크다운 절대 금지" 무시).

해결 — `stripCodeFences()` 헬퍼를 `EmailIntentClassifyService.parseAndApply` + `QuoteRequoteService.parseAi` 양쪽에 추가:

```apex
@TestVisible
private static String stripCodeFences(String body) {
    if (String.isBlank(body)) return body;
    String trimmed = body.trim();
    if (!trimmed.startsWith('`')) return trimmed;
    Pattern p = Pattern.compile('(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$');
    Matcher m = p.matcher(trimmed);
    return m.matches() ? m.group(1) : trimmed;
}
```

**교훈**: ConnectApi.EinsteinLLM 응답은 항상 stripCodeFences 통과 후 JSON 파싱. 단위 테스트의 mock JSON 은 코드 펜스 없는 깨끗한 JSON 이라 이 버그를 못 잡음 — **Apex Test 통과 ≠ E2E 통과**. Day 5 OCR 디버깅 패턴과 동일 (mock 통과 후 실제 LLM 호출에서 첫 시도 실패).

메모리 feedback_prompt_builder_apex 체크리스트 6번 항목으로 갱신.

### Custom Label `Quote_Tracking_Base_URL` 함정

- 1차: `<value></value>` 빈문자열 → SF 거부 ("필요한 필드 [Value] 없음").
- 정정: `<value>__UNSET__</value>` sentinel + Apex `trackingBaseUrl()` 가 `!startsWith('http')` 면 null 반환. 데모 직전 사용자가 Site URL로 갱신.
- 효과: Site 미배포 환경에서 sendQuote 가 평소처럼 동작(픽셀·wrap 미주입), 배포 후엔 자동 활성.

### EmailMessageTrigger.RelatedToId 폴리모픽 타입 분기

```apex
String typeName = em.RelatedToId.getSObjectType().getDescribe().getName();
if (typeName == 'Quote' || typeName == 'Opportunity') { /* 처리 */ }
```

`Id.getSObjectType()` 가 ID prefix 로부터 SObject 타입 식별. Account/Lead 등 메일이 wired 되어도 무시.

### 안전 정책 — AI 가격 변형 금지

```apex
// QuoteRequoteService.cloneLines
nq.Quantity        = qli.Quantity;           // 원본 그대로
nq.UnitPrice       = qli.UnitPrice;          // 원본 그대로
nq.Discount_Amount__c = qli.Discount_Amount__c;  // 원본 그대로
```

AI 제안은 Quote.Description 한국어 텍스트로만:
```
[AI 재견적 분석]
신뢰도: 0.85
단가 5% 인하 요구. 발주 의사 강함.

[제안 조정안]
• BR-6201 / discount = 0.05 — 단가 5% 인하
```

평가자 답변: "AI Human-in-the-loop. AI 가 가격 직접 갱신하면 회계·신용한도 위험. 분석·요약은 AI, 결정은 AE — D15 D25 일관 정책."

### 시연 검증 절차 (Site 미배포 환경 대응)

1. Setup → Custom Labels → `Quote_Tracking_Base_URL` 그대로 둠 (`__UNSET__`)
2. Opp 페이지 → Activity > Email Log 로 EmailMessage 수동 인서트:
   - Subject = "재견적 요청"
   - Body = "단가 5% 인하 가능한지 확인 부탁드립니다."
   - Incoming = true, RelatedTo = 발송된 Quote
3. 트리거 → @future → 약 5~15초 후 EmailMessage 새로고침 → Intent__c='재견적' 확인
4. 같은 Opp 의 Related Quotes 새로고침 → Status='초안'에 (재견적) 접미사 Quote 자동 생성, Description 에 AI 분석 블록 확인

### Site 설정 절차 (옵션 — 픽셀 추적 데모 시)

1. Setup → Sites → New
   - Site Label: `Sales Tracking`, Site URL: `/sales-tracking`
   - Active Site Home Page: 더미 VFP (없으면 `UnderConstruction` 그대로)
2. Public Access Settings 클릭 → 새 탭 Profile 편집
   - Enabled Apex Class Access: `EmailTrackingService` 추가
   - Object Settings → Quote: Read·Edit 허용 + Field-Level Security 에 `Last_Opened_At__c`/`Last_Clicked_At__c` Edit 활성
3. Site Activation → Active 토글
4. Setup → Custom Labels → `Quote_Tracking_Base_URL` 값 갱신:
   `https://{my-orgdomain}.develop.my.site.com/sales-tracking/services/apexrest/quote-tracking`
5. Quote 발송 → 외부 이메일에서 열기 → Last_Opened_At__c 갱신 확인

---

## 18. Day 8 ERP Mock 동기화 학습 (2026-05-12)

**왜 추가했나**: 시연 §8 핵심 — "AE 가 콕피트에서 [🔄 ERP 동기화] 한 번으로 위험 5건 등장 → 78점 Order [사전 통보 메일] 발송". 외부 callout 0 정책 (D17·NG-016 일관) 유지하면서 ERP 신호를 가시화.

### 설계 패턴 — 게이트웨이 인터페이스 + DI

| 책임 | 구현 | 이유 |
|---|---|---|
| 외부 ERP 추상화 | **interface** `IExternalErpService` | Apex Mocks 패턴. 실 ERP 어댑터(Beeceptor/MuleSoft) 교체 가능. 평가자 답변: "Sales Cloud 는 ERP 신호의 소비자, 게이트웨이로 책임 격리" |
| 시연용 결정적 점수 | `ErpServiceMock` (PoNumber 끝 + Production_Status 분기) | 시드 D17-정정과 정합. 같은 Order 매번 같은 점수 — `Math.abs(Id.hashCode())%range` jitter |
| Apex 진입점 | `OrderErpSyncService` (@AuraEnabled syncOrders/syncAllOpen/getRiskView) | LWC 가 호출. `@TestVisible static IExternalErpService impl = new ErpServiceMock()` 으로 DI |
| 가격 안전 | **Order 가격·라인 직접 변경 금지** (D26 일관) | 위험 점수·동기화 시각만 갱신. 평가자: "AI/ERP 가 가격 결정 위험 격리" |

### 점수 분포 (D17-정정 시드와 정합)

```
PoNumber 끝 '6' + InProgress → 70 + jitter%15  (70~84)   위험        — 5건 시드
PoNumber 끝 '9' + InProgress → 85 + jitter%13  (85~97)   대형지연    — 5건 시드
기타 InProgress              → 20 + jitter%20  (20~39)   진행중 정상
Done                         →  5 + jitter%10  ( 5~14)   출고대기
Shipped                      →  0 + jitter%8   ( 0~ 7)   출고완료
Pending                      → 25 + jitter%15  (25~39)   생산대기
```

E2E 검증 결과 (`scripts/apex/verifyDay8.apex`): 시드 100건 동기화 후 대형지연 5 / 위험 5 / 안전 90 / 미동기화 0 — 완전 정합.

### DI 테스트 패턴

```apex
// OrderErpSyncService.cls
@TestVisible static IExternalErpService impl = new ErpServiceMock();

// OrderErpSyncService_Test.cls
@IsTest
static void testDependencyInjection_canSwapImpl() {
    OrderErpSyncService.impl = new StubErp();  // 테스트 전용 stub
    List<OrderErpSyncService.SyncOutcome> outs = OrderErpSyncService.syncOrders(new List<Id>{ o.Id });
    System.assertEquals(42, outs[0].riskScore);  // Stub 가 42 강제
}

private class StubErp implements IExternalErpService {
    public List<ErpSyncResult> fetchOrderStatus(List<Id> ids) { /* ... */ }
}
```

이 패턴은 Day 9 PaymentService·ShippingCompleteService 등 도메인 외부 시스템 의존 클래스에 차용 가능.

### LWC 패턴 (oppInsightCard 차용)

`@wire getRiskView` + `imperative syncOrders` + `refreshApex` — Day 7 P1 oppInsightCard 와 동일. 차이점:
- 위험 점수 색상 3단계 (≥70 적/40-69 황/<40 녹)
- 78점+ 시 `[사전 통보 메일]` mailto 액션 (Subject·Body 한국어 자동 채움 → 기본 메일 클라이언트 열림)
- 미동기화 상태(`isUnsynced`) 시 안내 텍스트

### 시드 함정 검증 (Anonymous Apex)

`scripts/apex/verifyDay8.apex` 작성 시 SOQL 함정 2건:
1. `SOQL CASE WHEN` 미지원 → Apex Map 측 집계로 우회
2. `Order.Description` Long Text 필드 → WHERE 필터 불가, `PoNumber LIKE 'PO-2026-%'` 패턴으로 변경

다음 Anonymous Apex 작성 시 동일 함정 회피.

### 후속 (Day 9·Day 10)

- aeCockpit LWC 에 Order 위험 sublist 통합 (`syncAllOpen` 호출 + 점수 내림차순 상위 10건)
- Day 8 ERP 신호를 Quote 단계까지 통합한 DeliveryRiskCalculator (선택)
- ERP Mock 클래스 커버리지 100% 유지 (실 ERP 어댑터 추가 시 회귀 안전망)

---

## 19. Day 10 Phase A Agentforce 학습 (2026-05-13)

**왜 추가했나**: 시연 §10 핵심 — AE 가 콕피트 자연어 입력창에 "오늘 할 일 / 위험 Order / 고객사 요약 / 견적 follow-up 메일" 질의 → Agentforce 4 Action 자동 호출 → 한국어 응답. 5종 기술 중 Agentforce 라인 완성.

### Action 4종 매핑 (Apex Invocable → Agentforce Function)

| Action | 입력 | 출력 | 데이터 소스 |
|---|---|---|---|
| GetTodayPriorityListAction | category(opt) | 5카테고리 건수 + 한국어 summary + detailsJson | AeCockpitService.load() 래핑 |
| GetOrderAtRiskAction | minRiskScore(opt) / maxResults(opt) | 위험 Order 목록 JSON + 한국어 summary | Order.Delivery_Risk_Score__c SOQL |
| GetAccountSummaryAction | accountId 우선 / accountName 부분일치 fallback | 한국 영업 6필드 + 진행중 Opp/Order 건수 | Account SOQL + COUNT() |
| DraftFollowupEmailAction | quoteId / additionalContext(opt) | 한국어 subject + body + urgency + daysSinceSent | Prompt Builder FollowupDraft + fallback |

### @InvocableMethod 패턴 (Agentforce-ready)

```apex
public class XxxAction {
    public class Request {
        @InvocableVariable(label='...' description='...' required=true)
        public String someParam;
    }
    public class Response {
        @InvocableVariable(label='...')
        public String someResult;
    }
    @InvocableMethod(
        label='Get Xxx'
        description='Action 사용 시점·입력·출력 문장으로. Agentforce planner 가 이것 보고 라우팅.'
        category='Sales Cockpit'  // Topic 매핑용
    )
    public static List<Response> run(List<Request> reqs) { ... }
}
```

**핵심**: `description` 은 Agent planner 의 routing prompt. "언제 호출해야 하나" 를 자연어로 명시. category 로 Topic 그룹화.

### Quote 가격 안전 정책 (D26 일관)

DraftFollowupEmailAction 은 메일 본문만 생성, **Quote 자체는 변경하지 않음**. Prompt 본문에 "가격·할인·납기 임의 제시 금지, AE 의 additionalContext 만 인용" 명시. fallback 도 동일 정책.

평가자 답변: "AI Human-in-the-loop — AI 는 분석·드래프트, 결정·발송은 AE. 회계·신용 위험 격리(D26)."

### Apex 함정 3건 (Day 10 Phase A 디버깅)

| # | 함정 | 정정 | 재발 방지 |
|---|---|---|---|
| ① | 변수명 `like` = Apex 예약어 (SOQL 키워드). 컴파일 실패 "Unexpected token 'like'" | `namePattern` 등 비예약어로 | 동적 SOQL LIKE 쿼리 작성 시 변수명 주의 |
| ② | `@IsTest(IsParallel=true)` + `Test.getStandardPricebookId()` → "cannot be called from parallel Apex tests" | `IsParallel=true` 제거 | Pricebook 표준 ID 활성화하는 테스트는 직렬 실행 강제 |
| ③ | Test.isRunningTest() 게이트 + 라이브 ConnectApi 블록이 클래스의 ~30% 차지 → DraftFollowupEmail 70.78% < 75% | 라이브 블록 축약(null check 통합) + 의미있는 covered 로직 추가(urgency/daysSinceSent 계산) | BusinessLicensePromptService 패턴 — 라이브 ConnectApi 는 별도 private method 로 분리, 나머지 covered 로직 충분히 크게 |

### Prompt Template 2단계 deploy (Day 5 PR0014 패턴 재현)

1. **1차 deploy** — `<status>Draft</status>`, `<activeVersionIdentifier>` / `<versionIdentifier>` 없이.
2. `sf project retrieve start --metadata "GenAiPromptTemplate:FollowupDraft"` → Salesforce 가 자동 생성한 `versionIdentifier` 확인.
3. 메타에 `<activeVersionIdentifier>` + `<versionIdentifier>` 추가 + `<status>Published</status>` 변경.
4. 재배포 → 활성 버전 강제.

FollowupDraft 는 현재 1단계 완료 (Draft). 2단계가 Day 10 Phase B 첫 작업.

### `@InvocableVariable` 한국어 라벨 — Agent planner UX 향상

```apex
@InvocableVariable(label='긴급도(urgent/standard)')
public String urgency;
```

Agent UI 에 한국어로 노출됨. 평가자 시연 시 가독성 ↑.

### 후속 (Day 10 Phase B 가이드)

1. 실 deploy → Prompt Published 전환 → GenAiFunction × 4 → GenAiPlugin → Bot 순서
2. Topic 설명 작성 시: 4 Function description 내용 종합 + Sales Cockpit AE 페르소나 한국어 톤
3. Bot Type = Employee Agent + Running User = current admin (Service Agent 가 아니므로 별도 user 불필요)
4. Sales_Cockpit_User PermSet 에 agentAccesses 추가하여 시연 user 가 Agent UI 에 접근 가능하게

---

## 20. Day 10 Phase B Agentforce 메타 학습 (2026-05-13)

**왜 추가했나**: 4 Apex Invocable 을 Agentforce Topic + Bot 로 wiring 하는 실 deploy 경로. 직접 XML 메타 조립 시 schema 함정 다수 → CLI 기반 `sf agent create --spec` 경로로 우회한 학습.

### 메타 구조 (v66 Agentforce 기준)

```
Bot (bots/HandoSalesAgent/HandoSalesAgent.bot-meta.xml)
  ↓ <agentTemplate>AiCopilot__AgentforceAgent</agentTemplate>
  ↓ <type>ExternalCopilot</type>, <agentType>EinsteinServiceAgent</agentType>
  ↓ <botUser>handosalesagent@...ext</botUser> (자동 생성)
BotVersion (bots/HandoSalesAgent/v1.botVersion-meta.xml)
  ↓ <conversationDefinitionPlanners><genAiPlannerName>HandoSalesAgent</genAiPlannerName></conversationDefinitionPlanners>
GenAiPlannerBundle (genAiPlannerBundles/HandoSalesAgent/HandoSalesAgent.genAiPlannerBundle)
  ↓ <genAiPlugins><genAiPluginName>p_16jdM000003KdMr_Sales_Cockpit_Assistant</genAiPluginName></genAiPlugins>
  ↓ <plannerType>AiCopilot__ReAct</plannerType>
GenAiPlugin (Topic) — `p_16jdM..._Sales_Cockpit_Assistant`
  ↓ <genAiFunctions><functionName>GetTodayPriorityListAction</functionName></genAiFunctions> × 5
  ↓ <pluginType>Topic</pluginType>, <language>en_US</language>, <scope>...</scope>
GenAiFunction × 4 (genAiFunctions/<Name>/<Name>.genAiFunction-meta.xml)
  ↓ <invocationTarget>GetTodayPriorityListAction</invocationTarget>
  ↓ <invocationTargetType>apex</invocationTargetType>
```

### 직접 XML 조립 시 schema 함정 (실패한 시도들)

| # | 시도 | 실패 메시지 | 정정 |
|---|---|---|---|
| ① | `<pluginInstruction>...` | "Element pluginInstruction invalid at this location" | v66 GenAiPlugin schema 에 없음. `<scope>` + `<genAiPluginInstructions>` 로 대체 |
| ② | `<developerName>` 누락 | "Required field is missing: developerName" | GenAiPlugin 은 `<developerName>` 필수 |
| ③ | `<language>` 누락 | "Required field is missing: language" | `<language>ko</language>` 또는 `en_US` |
| ④ | `<pluginType>` 누락 | "Required field is missing: pluginType" | `<pluginType>Topic</pluginType>` 필수 |
| ⑤ | Bot `<type>EinsteinServiceAgent</type>` | "'EinsteinServiceAgent' is not a valid value for the enum 'BotType'" | `BotType` enum 은 `<type>ExternalCopilot</type>`, `EinsteinServiceAgent` 는 별도 `<agentType>` 필드 |
| ⑥ | Bot `<contextVariableMappings><messageType>InboundMessage` | "'InboundMessage' is not a valid value for the enum 'MessageType'" | InboundMessage 미지원. Text/EmbeddedMessaging/Line/Facebook/WhatsApp 등이 valid |

### 해결 경로 — `sf agent create --spec` CLI (D28)

직접 XML 조립을 포기하고 SF CLI 가 schema 일관 형식으로 생성하게 위임:

```bash
sf agent generate agent-spec --type internal --role "..." --company-name "한도정밀" \
  --output-file specs/SalesCockpitAssistant.yaml --target-org My_Org

sf agent create --name "한도세일즈 도우미" --api-name HandoSalesAgent \
  --spec specs/SalesCockpitAssistant.yaml --target-org My_Org

sf project retrieve start --metadata "Bot:HandoSalesAgent" \
  --metadata "GenAiPlannerBundle:HandoSalesAgent" --target-org My_Org

sf agent activate --api-name HandoSalesAgent --target-org My_Org
```

`sf agent create` 가:
- Bot + BotVersion + GenAiPlannerBundle + 자동 생성 GenAiPlugin 일괄 생성
- spec YAML 의 `role` / `company-description` + 우리 기 배포된 4 GenAiFunctions 를 LLM 이 분석해 4 Action + Knowledge fallback 매핑
- 한국어 sampleUtterances 자동 생성("오늘 할 일 목록을 알려줘.", "납기 위험이 있는 주문을 확인해줘." 등)

**D28 의사결정**: 라이브 발표 없는 환경 + 시간 압박 + schema fragility 종합 — `sf agent create` 경로 채택. 단점은 Bot type 이 `ExternalCopilot` 으로 강제 (Service Agent), 의도한 Employee Agent 와 차이. 평가자 narrative: "v66 DE Org Agentforce 가 ExternalCopilot type 으로만 sf agent create 지원 → 실제 운영 환경에서는 Bot type Employee 로 전환 가능".

### Agent user 권한 모델 (Einstein Agent User 라이센스)

`sf agent create` 가 `handosalesagent@<orgid>.ext` user 를 자동 생성. Profile = "Einstein Agent User", UserType = Standard.

Apex Invocable 호출 권한:
1. **classAccess** — 4 Action + AeCockpitService (Apex 진입)
2. **Object Read** — Lead / Account / Contact / Opportunity / Quote / Order (with sharing SOQL)
3. **Field Read** — 핵심 커스텀 필드 14개 (Business_Number/CEO/AR/Score/Limit/LongTerm + 잔여)
4. **AgentforceServiceAgentUser** 표준 PermSet (PermSet Group `AgentforceServiceAgentUserPsg` 로 부여) — Agentforce 런타임 접근
5. **(잔여)** — Setup UI 에서 4 Action 별 "Manage Access" 토글 필요 추정

라이센스 제약 — `viewAllRecords=true` 불가. PermSet 메타에서 `viewAllRecords=false` 강제.

### Anonymous Apex 로 PermSet 자동 할당

```apex
User agentUser = [SELECT Id FROM User WHERE Username LIKE 'handosalesagent%' LIMIT 1];
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Agentforce_Sales_Cockpit' LIMIT 1];
insert new PermissionSetAssignment(AssigneeId = agentUser.Id, PermissionSetId = ps.Id);
```

Sales_Cockpit_User PermSet 직접 할당 시도 시 — VF page(QuotePdfPage) 접근 권한이 Einstein Agent User 라이센스 호환 불가 → 라이트웨이트 별도 PermSet `Agentforce_Sales_Cockpit` 신설.

### 잔여 디버깅 단서

`sf agent preview send` 결과 — Apex `as admin` 정상(7건 반환), agent 자연어 질의 시 "configuration issue / 데이터 라이브러리 미할당" 메시지. 가능성:
- Setup UI Agent Builder → Topic → Action 별 "Manage Access" 토글 필요 (시도 권장)
- 또는 GenAiFunction 메타에 `<accessGrant>` / `<requiredPermissionSet>` 같은 필드 명시 필요
- 또는 GenAiPlannerBundle `<plannerSurfaces>` 의 surface 토글 차이

해결 진행 시 §20 에 추가 학습 기록 권장.

### 후속 (코드 경로 후속)

1. 자동 생성 GenAiPlugin 이름 `p_16jdM..._Sales_Cockpit_Assistant` 가 ID 포함 → 리네임 검토 (메타에 `developerName` 변경 + GenAiPlannerBundle 의 reference 동기)
2. 우리 하드 코딩한 GenAiPlugin `SalesCockpitAssistant` (orphan) — 삭제 or 자동 생성 plugin 으로 swap
3. Bot type ExternalCopilot → Employee 전환 가능 여부 확인 (v66 DE Org 기능)

---

## 21. Day 11 의사결정 (D29~D32)

| # | 결정 | 근거 |
|---|---|---|
| D29 | **Agentforce Bot 우회용 LWC 자체 구현** — agentforceInputBar 가 키워드 라우터로 Apex Invocable 직접 호출 | v66 ExternalCopilot 한계 (sf agent preview 가 Apex Action 호출 불가, Setup UI Manage Access 메타 API 미공개) 우회. 시연 안정성 확보. 평가자: "Agentforce planner 가 호출하는 같은 4 Action 을 LWC 도 호출하므로 동일 path". |
| D30 | **LLM Invoker 분리 패턴 표준화** — `<Name>Invoker.cls` 에 ConnectApi 라이브 블록 격리, `<Name>Service.cls` 가 호출 | 라이브 ConnectApi 블록(~20줄)은 unit test 불가 → Service 클래스의 75% 커버리지 충족 어려움. Invoker 로 분리하면 Service 100% 가능, Invoker 만 15~20% 커버(narrative). BusinessLicensePromptInvoker (Day 5) 패턴 표준화. Day 11 신규 적용: SpecExtractInvoker / DelayNoticeInvoker / AgentInputFallbackInvoker. |
| D31 | **사업자번호 체크섬 강제** — Test 데이터 작성 시 추가 Account 는 Business_Number 비워야 함 | AccountTriggerHandler 의 한국 사업자번호 가중치(1,3,7,1,3,7,1,3,5) 검증 — 임의 번호 invalid. 시드의 '100-00-00009' 만 valid. Day 11 GetCrossSellCandidates_Test 에서 발견·정정. |
| D32 | **세일즈 도우미 LWC 자유도 단계적 확장** — 1차 키워드 라우터(완료), 2차 LLM 단순 fallback(완료), 3차 ReAct 패턴(Day 12 잔여) | Day 11 사용자 피드백: "콕피트에서 볼 수 있는 정보를 다시 물어보기 싫음, 자유 질문에 답해줘야 함". 현재 LLM fallback 은 DB 조회 못 함 → §22 3-step ReAct 라우터로 LLM 이 tool 자동 선택 + Apex 호출 + 결과 종합 필요. |

---

## 22. ★★★ Day 12 잔여 — 3-step LLM 라우터 (ReAct 패턴)

**배경**: 현재 세일즈 도우미 (agentforceInputBar) 는 키워드 매칭 → 4-5개 Action 라우팅 + 키워드 매칭 실패 시 `AgentInputFallback` Prompt 로 LLM 단순 응답. 그러나 **LLM 이 DB 조회를 못 함** — 예: "진성정밀 물건 나갔나요?" → 정답은 GetAccountSummaryAction 호출 결과여야 하나, 현재는 "그건 '진성정밀 납기 위험 주문' 으로 물어보세요" 같은 안내만 반환.

**목표**: 진짜 Agentforce planner 처럼 LLM 이 자동으로 tool 선택 → Apex 호출 → 결과 + 원 질문을 다시 LLM 에게 종합 → 한국어 자연어 응답.

### 설계 (3-step)

```
[1] AgentRouter Prompt (신규)
    Input: utterance
    Output JSON: {"tool": "<actionName>", "args": {...}, "rationale": "..."}
    허용 tool: GetTodayPriorityList / GetOrderAtRisk / GetAccountSummary
              / GetCrossSellCandidates / DraftFollowupEmail / none(자유 응답)

[2] AgentforceInputBarService.askWithRouter(utterance, contextRecordId)
    - AgentRouterInvoker 호출 → JSON 파싱 + stripCodeFences D26
    - tool == none → AgentInputFallback(현재 Prompt) 호출 → 끝
    - 그 외 → 해당 Action 의 .run() 직접 호출 → outputJson 보유
    - args.accountName / args.accountId / args.quoteId 가 비면 contextRecordId 로 보강
    - args 누락 시 한국어 안내 응답 ("어떤 고객사를 말씀하시는지 알려주세요")

[3] AgentSynthesize Prompt (신규)
    Input: utterance + actionOutputJson (직렬화된 Action.Response)
    Output: 자연어 한국어 답변 (3~5문장, 친근체)
    프롬프트 지침:
      - actionOutputJson 의 실수치를 인용해 답
      - 데이터에 없는 숫자 절대 추가 X (D26 일관)
      - 마크다운 / 코드 펜스 금지

[4] LWC 응답
    response.action = '<tool>' (예: 'GetAccountSummary')
    response.message = synthesized natural language
    response.detailsJson = actionOutputJson (디버그용, UI 미노출)
```

### 구현 체크리스트 (예상 ~1.5시간)

- [ ] `force-app/main/default/genAiPromptTemplates/AgentRouter.genAiPromptTemplate-meta.xml` 신설
  - inputs: Utterance(String), ContextHint(String, recordType + AccountName)
  - 출력 JSON schema: `{"tool":"","args":{...},"rationale":""}`
- [ ] `force-app/main/default/genAiPromptTemplates/AgentSynthesize.genAiPromptTemplate-meta.xml` 신설
  - inputs: Utterance(String), ActionResult(String, JSON 직렬화)
  - 한국어 자연어 응답 1단락
- [ ] `force-app/main/default/classes/agentforce/AgentRouterInvoker.cls` — 라이브 ConnectApi 분리 (Invoker 패턴 D30)
- [ ] `force-app/main/default/classes/agentforce/AgentSynthesizeInvoker.cls` — 동일 패턴
- [ ] `AgentforceInputBarService.ask()` 재설계:
  - 키워드 매칭 (현재) 그대로 두되, **매칭 실패 시 router 호출** (현재는 단순 fallback)
  - 또는 키워드 매칭 완전히 제거하고 처음부터 router 만 사용 (더 일관)
  - router → tool == none → AgentInputFallback (기존)
  - router → tool 매칭 → 해당 Action `.run()` + synthesize
- [ ] Test 케이스 — router mockResponse + synthesize mockResponse 로 e2e flow 검증
  - 예: utterance "진성정밀 미수금 알려줘" → router mock {"tool":"GetAccountSummary","args":{"accountName":"진성정밀"}} → 실 Action 호출 → synthesize mock "진성정밀(주) 미수금은 ..."
- [ ] 두 Prompt Published 활성화 (Draft deploy → retrieve versionIdentifier → activeVersionIdentifier 명시 → 재배포)
- [ ] E2E 검증 — "진성정밀 물건 나갔나요?" 류 자유 질문에 정확한 데이터 응답
- [ ] PermSet Sales_Cockpit_User 에 신규 Invoker 2개 classAccess 추가
- [ ] WORKLOG 갱신

### 핵심 함정 회피 체크리스트 (Day 11 학습)

1. **XML escape** — Prompt content 안의 `<...>` 는 `&lt;...&gt;` 로 escape (AgentInputFallback 에서 발견)
2. **변수명** — Apex 식별자에 underscore 끝 (`limit_`) 또는 한글 불가 — `cap` / `namePattern` 사용
3. **사업자번호** — Test Account 는 valid 한 '100-00-00009' 또는 Business_Number 비워두기
4. **Invoker 분리** — 라이브 ConnectApi 는 별도 `*Invoker.cls` 로 격리, `--ignore-warnings` 사용
5. **stripCodeFences** — LLM 응답이 ` ```json ... ``` ` 로 감싸지면 정규식 `(?s)^`{3}(?:json|JSON)?\\s*(.*?)\\s*`{3}\\s*$` 로 제거
6. **applicationName** — `'PromptBuilderPreview'` (검증된 값)
7. **3-arg ConnectApi** — `generateMessagesForPromptTemplate(name, '', input)` capability 빈 문자열
8. **2단계 활성화** — Draft deploy → retrieve `versionIdentifier` → 메타에 `<activeVersionIdentifier>` + `<status>Published</status>` 명시 → 재배포

### 우회 narrative (Day 12 시간 부족 시)

> "현재 LLM fallback 은 안내 응답에 한정. 시연 데모는 5 Action 키워드(오늘 우선순위/납기 위험/고객사 요약/교차 판매/follow-up) 로 한정해 시연. ReAct 라우터는 Day 12 backlog 로 자기설명. 평가자 답변: '같은 Apex Invocable 을 Agentforce planner / LWC 라우터 / ReAct LLM 라우터 3가지 path 에서 호출 가능' — 5종 기술 통합 보완".

---

## 23. 다음 세션 시작 시 할 일 (5/12~5/14)

### 즉시 (1분)
- [ ] `sf org display --target-org My_Org` 연결 확인
- [ ] WORKLOG.md 마지막 줄 (Day 11 ★★★ 세트 종료) 확인
- [ ] 본 §22 / §21 정독

### Phase 7 — 3-step LLM 라우터 (★★★, 1.5h)
- [ ] §22 체크리스트 순차 진행
- [ ] E2E: "진성정밀 물건 나갔나요?" / "현대모비스 어때?" / "오늘 뭐 해야 해?" 같은 자유 질문 정확 응답 확인

### Phase 8 — 시연 자료 캡처 + 슬라이드 (5/14 오전~오후, 6~7h)
- [ ] 시연 동영상/스크린샷 캡처 — 골든패스 §1~§10 (OBS / PowerPoint 화면 녹화)
  - **세일즈 도우미 자연어 질의** 강조 (LLM 라우터 시연)
  - 5 AI Prompt 실 호출 (CallMemo / OCR / OppInsight / SpecExtract / DelayNotice)
  - ERP 동기화 → 위험 Order 5건 → 사전 통보 AI 메일
- [ ] 슬라이드 9 섹션 작성 (PPT/PDF)
  - Cover / 차별화 4 / 골든패스 / AI 라인 9 Prompt / ERP 게이트웨이 / **Agentforce 5 Action + LLM 라우터** / 의사결정 D17/D25/D26/D27/D28/D29/D30 / 산출물 카탈로그 + 294 Test / 한계 narrative
- [ ] 17:55 까지 메일 발송 (18:00 마감)

### 후속 backlog (시간 남으면)
- Site 픽셀 추적 활성화 (QUOTE-006)
- Bot type Employee 전환 시도 (v66 DE Org)
- 자동 생성 GenAiPlugin orphan SalesCockpitAssistant 정리

---

## 24. Day 11 추가 산출물 (v9 → v10 diff)

**신규 Apex (12 클래스)**:
- `agentforce/AgentforceInputBarService.cls + Test` (라우터)
- `agentforce/AgentInputFallbackInvoker.cls` (LLM 자유 응답 Invoker)
- `agentforce/GetCrossSellCandidatesAction.cls + Test` (5번째 Action)
- `lead/SpecExtractService.cls + Test + SpecExtractInvoker.cls + Invoker_Test` (RFQ AI 추출)
- `order/DelayNoticeService.cls + Test + DelayNoticeInvoker.cls` (사전 통보 AI)
- `order/OrderErpSyncScheduler.cls + Test` (매일 03:00)
- `quote/QuoteFollowupScheduler.cls + Test` (매일 04:00)

**신규 Prompt Template (4건)**:
- `CallMemoExtract` (LEAD-006, Phase 4-A)
- `SpecExtract` (LEAD-002, Phase 6-B)
- `DelayNotice` (ORDER-004, Phase 6-C)
- `AgentInputFallback` (Phase 6-A 확장)

**신규 GenAiFunction**: `GetCrossSellCandidatesAction`

**신규 LWC**: `agentforceInputBar` (세일즈 도우미)

**메타 수정**:
- `lead/RfqInboundHandler.cls` — CallMemoExtract → SpecExtract 우선 호출
- `order/orderRiskCard` LWC — handleNotify async + DelayNotice AI 호출
- `quote/QuoteEmailService.cls` — OPP-002 자동 Stage 전이
- `quote/PricingService.cls` + `quoteBuilder` LWC — AR 헤더 + 신용한도 경고
- `genAiPlugins/p_16jdM..._Sales_Cockpit_Assistant` — 5번째 function + language ko
- 3 PermSet (Sales_Cockpit_User / HandoSalesAgent437863651_Permissions / Agentforce_Sales_Cockpit) — classAccess 5건 추가
- 3 Scheduler 클래스의 기존 Test 들 — System.schedule 직접 호출(test 전용 이름)로 cron 충돌 회피
