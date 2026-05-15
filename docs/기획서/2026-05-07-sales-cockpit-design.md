# Lead-to-Cash 영업 콕피트 — 한도정밀(가칭) 기획서

**문서 버전**: v0.1 (초안)
**작성일**: 2026-05-07
**제출 예정**: 2026-05-14 (오후)
**대상**: B2B 부품/소재 제조업 영업 담당자 (AE)
**플랫폼**: Salesforce Sales Cloud + Agentforce + Prompt Builder

---

## 1. 개요 (Executive Summary)

### 1.1 한 줄 요약

> **"제조업 영업 담당자가 Lead 인입부터 미수금 회수까지 끝까지 책임지는 흐름을, 단 하나의 워크스페이스에서 AI Human-in-the-loop으로 처리하게 하는 Sales Cloud 솔루션."**

### 1.2 굳이 이렇게 개발해야 하는 이유

B2B 부품/소재 제조업의 영업 담당자는 RFQ 응대부터 견적·결재·납기 약속·세금계산서·미수금 회수까지 **고객과의 모든 약속을 끝까지 책임진다**. 그러나 현실에서 이 흐름은 **메일·엑셀·메신저·전화·ERP 화면·결재 시스템에 흩어져** 있다.

본 솔루션은:
1. 흩어진 흐름을 **하나의 워크스페이스**로 통합한다.
2. AI는 **자유 텍스트 영역**(RFQ 사양 추출·메일 의도 분류·메일 작성)에만 한정 투입해 영업의 입력 부담을 90% 감축한다.
3. ERP·생산·품질 영역은 **Mock 게이트웨이**로 격리해 Sales Cloud 색깔을 유지한다.

### 1.3 대상 사용자

**페르소나: AE 김민수 (35세, 영업 5년차) @ 한도정밀**
- 자동차/전자 부품용 정밀 가공품 제조사
- 거래처 30개 담당, 월 RFQ 평균 25건
- 책임 범위: Lead 인입 → Quote → Won → 결재 → 생산팀 인계 → 납기 약속 → 세금계산서 → 미수금 회수 → Cross-sell

---

## 2. 비즈니스 컨텍스트

### 2.1 도메인 — 부품/소재 제조업의 영업 사이클

```
[고객 RFQ 메일]      ──┐
                     ├→ Lead → Opp → Quote → 발송·추적
[입찰 공고] (Tier 2) ──┘                ↓
                            [Won] 내부 결재(계약금액 조정)
                                ↓
                            결재완료 → 생산팀 인계메일
                                ↓
                            ─── ERP 시야 밖 (Mock) ───
                            (생산 → 품질검사 → 출고)
                                ↓
                            출고 시그널 → 세금계산서 발행
                                ↓
                            입금 추적 → 3/4/5개월 알림 → 6개월 장기채무
                                ↓
                            Cross-sell / 갱신 (AR 잔액 + 신용한도)
```

### 2.2 영업의 시야 vs ERP의 시야 (경계선)

| 영역 | 영업(✅ 본 시스템) | ERP/생산/회계(❌ Mock 게이트웨이) |
|---|---|---|
| RFQ 접수·견적·발송 | ✅ | |
| 계약 결재·금액 조정 | ✅ | |
| 생산팀 인계 메일 | ✅ | |
| 실제 생산 일정·작업지시·자재 차감 | | ❌ (Mock에서 시그널만) |
| 품질 검사·합격 판정 | | ❌ (Mock에서 결과만) |
| 출고 워크플로우 | | ❌ (Mock에서 완료 시그널만) |
| 세금계산서 발행 요청·고객 안내 | ✅ | |
| 매출 인식·분개·세금 계산 | | ❌ (회계 영역) |
| 입금 추적·미수금 응대 | ✅ | |
| 신용한도·Cross-sell 의사결정 | ✅ | |

**원칙**: ERP의 워크플로우 결과를 **고객 응대 시그널**로 변환하는 게이트웨이 역할만 한다. 생산·품질·자재·회계 자체는 만들지 않는다.

---

## 3. 사용자 Pain Points

### 3.1 12개 Pain Points

| # | 단계 | Pain Point | Tier |
|---|---|---|---|
| 1 | RFQ 인입 | 메일·도면 → SKU 매칭 수작업 (1건당 30분~1시간) | T1 |
| 2 | Qualify | 신규 고객사 신용도·과거 거래 깜깜이 | T1 |
| 3 | Quote 작성 | 단가·할인·MOQ·PDF 수작업 | T1 |
| 4 | Approval | 할인율 승인이 메신저로 따로따로, 추적 안 됨 | T1 |
| 5 | Quote 추적 | 발송 후 응답 없음·진행 상황 깜깜이 | T1 |
| 6 | Won 후 결재 | 계약금액 최종 조정 + 매니저 결재 + 생산팀 인계 | T1 |
| 7 | 납기 위험 | 지연 시 고객 사전 통보 누락 | T1 |
| 8 | 세금계산서 | 출고 후 청구 워크플로우 분산 | T1 |
| 9 | 미수금 단계화 | 3/4/5개월 응대·6개월 장기채무 분리 | T1 |
| 10 | 신용한도 | AR 잔액 기반 신규 견적 홀딩 판단 부재 | T1 |
| 11 | Cross-sell | 납품 완료 후 추가 영업 시점 놓침 | T2 |
| 12 | Lost 분석 | 사유 정리·재활용 안 됨 | T2 |

**Tier 1 = 시연 골든패스 (반드시 완성)**, **Tier 2 = stretch**

### 3.2 페르소나의 하루 (시간순)

| 시간 | 활동 | 본 솔루션의 대응 |
|---|---|---|
| 09:00 | 어제 인입된 RFQ 5건 확인 | 콕피트에 카드로 자동 정렬 (긴급도+신용도) |
| 09:30 | 견적 1건 작성 | AI 초안 1분 안에 표시, AE는 1줄만 수정 |
| 11:00 | 응답 없는 견적 follow-up | Flow가 N일 무응답 자동 알림 |
| 13:00 | Won 처리 + 매니저 결재 | LWC에서 인라인 결재, 결재완료 시 생산팀 인계메일 자동 |
| 15:00 | 납기 임박 Order 점검 | 콕피트에 위험 점수로 표시, 사전통보 메일 초안 제공 |
| 17:00 | 미수금 응대 | 3/4/5개월차 자동 단계 메일 진행, AE는 톤만 검토 |
| 18:00 | "이번 주 우선순위?" Agentforce에 질의 | 자연어로 한눈 정리 |

---

## 4. 솔루션 차별화 (비즈니스 가치 / 특별한 점)

### 4.1 4가지 차별화 포인트

1. **L2C 통합 워크스페이스**
   - 보통 Sales 데모는 Won에서 끝남. 본 솔루션은 **Won 이후 미수금 회수까지** 영업 관점에서 다룸.
   - 다른 조원이 잘 안 다룰 영역.

2. **AI Human-in-the-loop Quote**
   - AI가 견적 초안 자동 작성, AE는 라인별 한 번씩만 확인·수정.
   - AE 입력 부담 90% 감소, **최종 책임만 남김**.

3. **ERP 게이트웨이 패턴**
   - ERP/생산/품질 영역을 직접 만들지 않고 **Mock 인터페이스**로 격리.
   - 영업이 시그널을 받아 **고객 응대로 변환**하는 단일 책임.
   - Sales Cloud 색깔 유지하면서 전 흐름 커버.

4. **미수금 단계화 응대**
   - 3개월(우호) → 4개월(정중) → 5개월(엄중) → 6개월(장기채무 상태 전환) 자동 진행.
   - Prompt Builder가 톤 단계화, AE는 발송 직전 한 번 확인.

### 4.2 평가 기준별 강점 매핑

| 평가 기준 | 본 시스템의 답 |
|---|---|
| 서비스 완성도 (디자인·기능 흐름) | L2C 풀 흐름, 콕피트 일관 UX, 시연 골든패스 6분 완성 |
| 비즈니스 가치 (특별한 점) | §4.1의 4가지 차별화 |
| 사용자 관점 (페르소나·UX) | AE 김민수 명확, 입력 부담 90% 감축 디자인 원칙 |
| 아키텍처 설계 | ERP 게이트웨이로 결합도 ↓, 컴포넌트 단위 모듈화 |
| 기술 선택 적절성 | §5.3 5종 정당성 매트릭스 (안티패턴 회피) |
| 코드 및 구조 품질 | 작은 LWC 분리, Apex 인터페이스 격리, Flow 시각화 |

---

## 5. 시스템 아키텍처

### 5.1 전체 구조

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Salesforce Sales Cloud + Agentforce              │
│                                                                     │
│  ┌─────────────────────┐         ┌──────────────────────────┐       │
│  │  AE Cockpit (LWC)   │◄───────►│  Agentforce Copilot      │       │
│  │  - RFQ Card         │         │  (자연어 횡단 질의)      │       │
│  │  - Order Risk Card  │         └──────────────────────────┘       │
│  │  - AR Action Card   │                    │                       │
│  │  - Lead Priority    │                    ▼                       │
│  │  - Approval Panel   │         ┌──────────────────────────┐       │
│  └──────────┬──────────┘         │  Prompt Builder Templates│       │
│             │                    │  - SpecExtract           │       │
│             ▼                    │  - IntentClassify        │       │
│  ┌─────────────────────┐         │  - HandoffMail           │       │
│  │  Quote Builder LWC  │◄────────┤  - DelayNotice           │       │
│  │  (AI Draft + Edit)  │         │  - DunningTone3/4/5      │       │
│  └──────────┬──────────┘         │  - LostCategory          │       │
│             │                    └──────────────────────────┘       │
│             ▼                                                       │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │  Apex Services                                          │        │
│  │  - PricingService (단가·할인·신용한도 계산)             │        │
│  │  - QuotePdfService (PDF 생성)                          │        │
│  │  - EmailTrackingService (오픈/클릭)                    │        │
│  │  - LeadScoringService                                  │        │
│  │  - IExternalErpService (인터페이스, Mock 구현체)       │        │
│  └────────────────────────┬────────────────────────────────┘        │
│                           │                                         │
│  ┌────────────────────────▼────────────────────────────────┐        │
│  │  Flow Automations                                       │        │
│  │  - Lead Convert / Stage Transition                      │        │
│  │  - Approval Process (Quote 결재)                        │        │
│  │  - Email Followup (N일 무응답)                          │        │
│  │  - Delivery Risk Check (N-7일 전)                       │        │
│  │  - Invoice Trigger (출고 시그널 시)                     │        │
│  │  - AR Stage Escalation (3/4/5/6개월)                    │        │
│  └─────────────────────────────────────────────────────────┘        │
│                                                                     │
└────────────────────────────────────┬────────────────────────────────┘
                                     │
                                     ▼ (HTTP Callout, Mock)
                       ┌───────────────────────────┐
                       │  External ERP Mock        │
                       │  (Beeceptor 또는 Apex Mock)│
                       │  - GET production/schedule│
                       │  - GET ar/balance         │
                       │  - GET catalog/sku        │
                       │  - POST shipping/done     │
                       └───────────────────────────┘
```

### 5.2 아키텍처 의사결정 (Trade-off)

#### Decision 1: LWC 배치 — 콕피트형 vs 표준 페이지 임베드형

| 옵션 | 장점 | 단점 | 선택 |
|---|---|---|---|
| A. 통합 콕피트 (Lightning App Page) | 한 화면에 모든 컨텍스트, 강한 UX | 표준 객체 페이지와 단절 위험 | |
| B. 표준 페이지 임베드 (각 객체 페이지에 위젯) | Sales Cloud 색깔 강함, 표준 활용 | 페이지 간 이동 부담 | |
| **C. 하이브리드 (콕피트 Home + 표준 페이지 위젯)** | 일별 우선순위 + 단계별 디테일 양립 | 약간의 결정 복잡도 | **✅** |

→ **C 선택**: 콕피트는 "오늘 무엇을 할지", 표준 페이지는 "한 건의 디테일". 둘이 서로 보완.

#### Decision 2: AI 호출 경로 — Apex가 호출 vs Agentforce/Flow가 직접 호출

| 옵션 | 장점 | 단점 | 선택 |
|---|---|---|---|
| A. Apex가 Prompt Template 호출 (Connect API) | 입출력 검증·로깅 통제 | Apex 코드 늘어남 | |
| **B. Flow/Agentforce가 직접 Prompt Template 호출** | 표준 통합, 유지보수 좋음 | 복잡 입력 가공 시 별도 처리 필요 | **✅ 기본** |
| C. 혼합 | 단계마다 적합한 경로 선택 | 일관성 ↓ | |

→ **B 기본 + 복잡 케이스만 A**: 단순 호출은 Flow, RFQ 메일 사전 가공이 필요한 경우만 Apex.

#### Decision 3: ERP 격리 방식

| 옵션 | 장점 | 단점 | 선택 |
|---|---|---|---|
| A. Apex Mock 클래스 | 콜아웃 비용 0, 시연 안정 | 외부 시스템 색깔 약함 | |
| **B. Beeceptor 등 외부 Mock + Apex Interface** | 진짜 콜아웃·Named Credential 시연 | 네트워크 의존 | **✅** |
| C. Platform Event | 비동기성 강조 | 시연 복잡 | |

→ **B 선택**: `IExternalErpService` 인터페이스로 추상화, Mock 구현은 Beeceptor를 호출. **Named Credential + Apex HTTP Callout** 패턴이 평가에서 가산점.

### 5.3 5종 기술 매핑 + 정당성 매트릭스

| 기술 | 사용 위치 | 없으면 어떻게 안 편한가 (정당성) |
|---|---|---|
| **LWC** | Quote 빌더 (AI 초안 + 인라인 편집 + PDF 미리보기) | 표준 Quote 페이지는 inline edit 약하고 PDF 미리보기 없음 → 5개 탭 순회 |
| **LWC** | AE 콕피트 (다중 객체 우선순위 통합) | List View 5개 매일 순회, Home 표준 컴포넌트로는 불가 |
| **LWC** | Order Schedule Tracker (분할 납품 시각화) | 표준 Related List로는 일정 시각화 불가 |
| **Apex** | 외부 API 콜아웃 + 단가/신용한도 계산 + Quote PDF | Flow Callout은 복잡 응답 파싱 한계, PDF 표준 한계 |
| **Apex** | Lead Scoring 로직 | 다중 외부 보강 + 가중치 계산은 Flow에 부담 |
| **Flow** | Lead Convert · Stage 전이 · 할인 승인 라우팅 | Sales Cloud 정석, Apex로 짜면 "날개발" |
| **Flow** | 시간 기반 자동화 (미수금 3/4/5개월, 납기 N-7) | 비즈니스 룰 시각화 → 매니저도 수정 가능 |
| **Prompt Builder** | RFQ 메일/도면 → 사양 추출 + SKU 매칭 | 자유 텍스트(부품명·공차·재질) → 룰 기반 한계, **LLM 진짜 필요** |
| **Prompt Builder** | 응답 메일 의도 분류 (6+ 카테고리) | 키워드 룰로 한계, 컨텍스트 의존 분류 필요 |
| **Prompt Builder** | 미수금 톤 단계화 메일 (우호→정중→엄중) | 같은 사실 다른 톤 자연스럽게 → 템플릿 3종보다 LLM이 자연스러움 |
| **Prompt Builder** | 생산 인계 메일·납기 사전통보 메일 자동 작성 | 자유 텍스트 생성 → LLM 정석 |
| **Agentforce** | AE 자연어 횡단 질의 ("이번 주 납기 위험 Order") | SOQL을 AE가 못 씀, List View 조합 폭발, 자연어 NLP 진짜 가치 |

**안티패턴 회피 체크 ✅**
- "환불/배송 단순 카테고리 분기"처럼 **단순 분기에 LLM** 쓰는 부적절 케이스 **없음**
- LLM은 항상 **자유 텍스트 → 구조** 또는 **자유 텍스트 생성** 영역에만 사용
- Flow는 **정형 워크플로우(승인·시간기반·Stage전이)**, Apex는 **계산·외부 통합**, LWC는 **사용자 입력·시각화** — 각자 강점 영역만

---

## 6. 데이터 모델

### 6.1 표준 객체 활용

| 객체 | 역할 |
|---|---|
| `Lead` | RFQ 인입(메일/입찰) 최초 진입점 |
| `Account` | 고객사 (다중 키맨) |
| `Contact` | 구매·엔지니어·결재자 등 키맨 |
| `Opportunity` | 수주 기회, Stage 전이 |
| `Quote`, `QuoteLineItem` | 견적서, 견적 라인 |
| `Order`, `OrderItem` | 수주 후 주문, 분할 납품 라인 |
| `Product2`, `Pricebook2`, `PricebookEntry` | SKU 카탈로그·단가 |
| `EmailMessage`, `Task`, `ContentVersion` | 이메일 기록·할일·도면 첨부 |

### 6.2 커스텀 객체

| 객체 | 목적 | 핵심 필드 |
|---|---|---|
| `Invoice__c` | 세금계산서 (한 Order에 분할 발행 가능) | `Order__c` (Lookup), `Invoice_No__c`, `Issued_Date__c`, `Amount__c`, `Status__c` (발행대기/발행/입금완료) |
| `Payment__c` | 결제 추적 (Invoice에 N건) | `Invoice__c` (Lookup), `Promised_Date__c`, `Paid_Date__c`, `Paid_Amount__c`, `Status__c` (약속/입금/연체) |
| `Bid_Notice__c` (T2) | 입찰 공고 자동 인입 | `Source__c`, `Deadline__c`, `Estimated_Amount__c`, `Lead__c` |

### 6.3 커스텀 필드 (표준 객체 확장)

| 객체 | 필드 | 용도 |
|---|---|---|
| `Account` | `Credit_Limit__c` (Currency) | 신용 한도 |
| `Account` | `Total_AR__c` (Currency, Roll-up Summary) | 총 미수금 |
| `Account` | `Long_Term_Debtor__c` (Checkbox) | 6개월 이상 장기채무 플래그 |
| `Account` | `External_Credit_Score__c` (Number) | 외부 보강 신용점수 |
| `Account` | `Last_Payment_Date__c` (Date) | 최근 입금일 |
| `Lead` | `Source_Channel__c` (Picklist: RFQ/Bid) | 인입 채널 |
| `Lead` | `Lead_Score__c` (Number) | Apex 계산 점수 |
| `Lead` | `RFQ_Spec_JSON__c` (Long Text) | Prompt Builder가 추출한 사양 |
| `Opportunity` | `Bid_Channel__c` (Checkbox) | 입찰 인입 여부 |
| `Quote` | `AI_Draft_Confidence__c` (Number) | AI 초안 신뢰도 |
| `Quote` | `AE_Edit_Count__c` (Number) | AE가 수정한 라인 수 |
| `Order` | `Production_Status__c` (Picklist) | Mock ERP 시그널 매핑 |
| `Order` | `Production_Start_Date__c`, `Production_End_Date__c` (Date) | Mock ERP에서 동기화 |
| `Order` | `Delivery_Risk_Score__c` (Number) | 납기 위험 점수 |
| `Order` | `Handoff_Email_Sent__c` (Checkbox) | 생산팀 인계 발송 여부 |

### 6.4 ERD 요약

```
Lead ──(Convert)──► Account ◄──── Contact (다중)
                       │
                       ├── Opportunity ──► Quote ──► QuoteLineItem
                       │       │              │
                       │       └──(Won)──► Order ──► OrderItem
                       │                       │
                       │                       └──► Invoice__c (1:N)
                       │                              │
                       │                              └──► Payment__c (1:N)
                       │
                       ├── Credit_Limit__c, Total_AR__c, Long_Term_Debtor__c
                       │
                       └── (T2) Bid_Notice__c ──► Lead
```

---

## 7. 핵심 기능 상세 (Tier 1)

### 7.1 RFQ 인입 + AI Quote 초안 (Pain 1, 3)

**흐름**:
1. 인바운드 RFQ 메일이 Email-to-Case 또는 Email Service로 도착 → `Lead` 생성
2. `Apex Trigger`가 Prompt Builder 템플릿 `SpecExtract` 호출 → 부품명·수량·공차·재질·납기 추출 → `Lead.RFQ_Spec_JSON__c` 저장
3. AE가 콕피트에서 RFQ 카드 클릭 → Quote Builder LWC 진입
4. LWC가 `PricingService` 호출 → SKU 매칭 + 단가 + MOQ + 할인 → 견적 라인 자동 생성
5. AE가 라인별 1초씩 확인·수정 → "발송" 클릭 → `QuotePdfService`가 PDF 생성 → 이메일 발송

**기술**:
- LWC `quoteBuilder` (메인 컨테이너), `quoteLineEditor` (라인 단위 컴포넌트), `pdfPreview`
- Apex `PricingService.calculateQuoteLines(spec)`, `QuotePdfService.generate(quoteId)`
- Prompt Builder `SpecExtract` (입력: 메일 본문 + 첨부 텍스트, 출력: JSON)

### 7.2 견적 추적 + 응답 의도 분류 (Pain 5)

**흐름**:
1. Quote 발송 시 `EmailTrackingService`가 추적 픽셀·링크 삽입
2. 고객이 메일 열람·링크 클릭 → 콜백 → `Quote.Last_Engagement__c` 갱신
3. N일 무응답 시 `Flow`가 AE에게 알림 + follow-up 메일 초안 제안
4. 고객이 응답 메일 보내면 `Prompt Builder IntentClassify` 호출 → 6 카테고리(재견적/조건확인/거절/일정/확인/기타) 분류
5. 분류 결과에 따라 콕피트 카드 색상·우선순위 변경

### 7.3 Won → 결재 → 생산팀 인계 (Pain 6)

**흐름**:
1. Opportunity Stage `Won`으로 전이 → Approval Process 자동 시작
2. AE가 LWC Approval Panel에서 최종 계약금액 조정 (할인 추가) + 의견 기록
3. 매니저가 Lightning Email Approval 또는 모바일에서 승인
4. 승인 완료 → `Flow`가 생산팀(Production_Liaison 프로파일) 그룹 메일 발송
5. 메일 본문은 `Prompt Builder HandoffMail`가 자동 작성 (Quote 정보 + AE 노트 → 인계 메일 포맷)
6. 도면 등 ContentVersion 첨부 자동

### 7.4 납기 위험 + 사전 통보 (Pain 7)

**흐름**:
1. 매일 새벽 `Flow`가 진행 중 Order 전체 순회 → `IExternalErpService.getProductionSchedule(orderId)` 호출
2. 응답으로 `Production_Start_Date__c`, `Production_End_Date__c` 동기화 → `Apex DeliveryRiskCalculator`가 위험 점수 계산
3. `Delivery_Risk_Score__c` ≥ 70 또는 약속일 N-7 이내인 Order는 콕피트의 Order Risk Card에 노출
4. AE 클릭 → `Prompt Builder DelayNotice`가 고객 사전 통보 메일 초안 생성 (수주번호·원래 약속일·예상 지연일·재협상 옵션)
5. AE가 검토·발송

### 7.5 출고 시그널 → 세금계산서 (Pain 8)

**흐름**:
1. ERP Mock이 출고 완료 시 `POST /shipping/done` Webhook 호출 (Apex REST 수신)
2. `Order.Production_Status__c = 'Shipped'`로 전이 → `Flow`가 `Invoice__c` 자동 생성
3. AE가 콕피트의 Invoice 카드에서 분할 발행 옵션 선택 (분할 시 N건 생성)
4. 세금계산서 발행 task → 회계 담당자 (Mock 알림)
5. Invoice 상태 → "발행" → 고객사 안내 메일 자동 (선택)

### 7.6 미수금 단계화 응대 (Pain 9, 10)

**흐름**:
1. `Invoice.Issued_Date__c` 이후 매일 `Flow`가 경과일 점검
2. 90일 → AE에게 task + `Prompt Builder DunningTone3` (우호 톤) 메일 초안
3. 120일 → `DunningTone4` (정중 톤)
4. 150일 → `DunningTone5` (엄중 톤) + 매니저 알림
5. 180일 → `Account.Long_Term_Debtor__c = true` + 매니저·재무 그룹 알림 + 신규 Quote 생성 시 경고
6. AE가 새 Quote 작성 시 `PricingService.checkCreditLimit(accountId, quoteAmount)` 자동 호출 → 신용한도 초과 시 발송 블록 + 매니저 결재 필요

### 7.7 AE 콕피트 (전 단계 통합 UI)

**Lightning App Page** "Sales Cockpit" (Home page)
- **상단**: AE 환영 메시지 + Agentforce Copilot 입력창
- **좌측 컬럼 (오늘 처리)**: RFQ Card (인입 RFQ + AI 매칭률), Approval Panel (대기 결재)
- **중앙 컬럼 (진행 모니터링)**: Quote Tracking Card (응답 없는 견적), Order Risk Card (납기 위험)
- **우측 컬럼 (자금 관리)**: AR Action Card (Invoice 발행 대기 + 미수금 3/4/5/6개월 단계별), Lead Priority Card (자격검증 필요 Lead)
- **하단**: 최근 활동 피드

각 카드는 독립 LWC. 카드 클릭 시 표준 객체 페이지로 이동하거나 Quote Builder 등 전용 워크스페이스 열림.

---

## 8. 권한 및 프로파일

| 프로파일 | 권한 | 비고 |
|---|---|---|
| **Sales Rep** | Lead/Account/Contact/Opportunity/Quote CRUD, Order R, Invoice CRUD, Payment R | 견적 생성·발송 가능 |
| **Sales Manager** | Sales Rep + Approval, 모든 영업 데이터 R | Quote 결재 가능 |
| **Production Liaison** | Order R, ContentVersion R | 인계메일 수신 그룹 |
| **System Admin** | All | 설정 |

**Permission Sets**
- `Sales_Cockpit_User`: LWC 콕피트 접근 + Apex Service 실행 권한
- `Sales_Cockpit_Manager`: 결재·신용한도 변경 권한 추가

**원칙**: 견적 생성은 영업만 / 결재 승인은 매니저만 (사용자 요구 반영).

---

## 9. 시연 골든패스 (6분 데모)

**시점**: 화요일 오전, AE 김민수가 콕피트를 연다.

| # | 시간 | 액션 | 보이는 것 |
|---|---|---|---|
| 1 | 0:00 | 콕피트 열기 | 오늘의 우선순위 카드 6개 표시 |
| 2 | 0:30 | RFQ Card "현대모비스 — 베어링 100EA" 클릭 | Quote Builder가 AI 초안과 함께 열림 (3 라인 자동 생성, 신뢰도 92%) |
| 3 | 1:30 | 라인 2의 단가 -3% 조정 → "발송" 클릭 | PDF 미리보기 → 이메일 발송 완료 |
| 4 | 2:00 | 콕피트로 돌아옴 → 어제 발송한 Quote 응답 도착 | "재견적 요청" 분류로 Quote 카드 노란색 표시 |
| 5 | 2:30 | Won 처리 + 결재 패널에서 -5% 할인 추가 → 매니저 승인 | 승인 완료 → 생산팀 인계 메일 자동 발송 (도면 첨부됨) |
| 6 | 3:30 | Order Risk Card "납기 D-5 / 위험 78점" 클릭 | DelayNotice가 고객 사전 통보 메일 초안 표시 → AE 검토·발송 |
| 7 | 4:30 | AR Action Card "포스코 — 미수 95일" 클릭 | DunningTone3 우호 톤 초안 표시 → AE 발송 |
| 8 | 5:00 | Agentforce에 자연어 질의: "이번 주 납기 위험 큰 거래처 알려줘" | 자연어 응답 + 관련 Order 리스트 |
| 9 | 5:30 | "현대모비스 cross-sell 후보 알려줘" | 과거 거래 패턴 기반 SKU 추천 (T2, 시간 남으면) |
| 10 | 6:00 | 종료 |  |

---

## 10. 개발 우선순위

### 10.1 Tier 1 (필수, 시연 골든패스 단계 1~8)

1. 표준 객체 + 커스텀 객체/필드 정의·배포
2. Permission Sets, Profiles
3. Lead 인입(이메일 또는 Web-to-Lead) + Apex `LeadScoringService` + Prompt Builder `SpecExtract`
4. LWC `quoteBuilder` + `pricingService` + Prompt Builder 연동
5. LWC `aeCockpit` + 6개 카드 LWC
6. Quote Approval Process + LWC `approvalPanel`
7. ERP Mock(Beeceptor) + `IExternalErpService` + Apex 구현체
8. Flow: Stage 전이, 할인 승인, 견적 무응답 follow-up
9. Order 생성 자동화 + `DeliveryRiskCalculator` + Prompt Builder `DelayNotice`
10. Invoice/Payment 모델 + AR 단계화 Flow + Prompt Builder `DunningTone3/4/5`
11. Agentforce Topic + Action 정의 (자연어 횡단 질의)
12. Apex Test Class (org-wide 80%+)

### 10.2 Tier 2 (Stretch)

- Cross-sell 추천 (과거 거래 패턴 기반)
- Lost 사유 분류 (Prompt Builder `LostCategory`)
- 입찰 채널 자동 인입 (`Bid_Notice__c`)
- 모바일 LWC 최적화

---

## 11. 리스크 및 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| 12개 Pain Points 1주 완성 부담 | 시연 깊이 ↓ | Tier 1만 완성도 우선, Tier 2는 stretch |
| Prompt Builder 출력 품질 불안정 | UX 손상 | Few-shot 예시 강화 + AE의 "수정 가능" 디자인 원칙 (Human-in-the-loop) |
| ERP Mock 외부 의존 (Beeceptor) | 시연 중 다운 | Apex Mock 백업 구현 + try/catch 처리 |
| 거대 LWC 컴포넌트 위험 | 코드 품질 ↓ | 카드 단위 분리, prop 기반 통신 |
| Approval Process · Flow 충돌 | 자동화 꼬임 | Approval은 표준, Flow는 Stage 변경 후만 발화 |
| Agentforce 응답 정확도 | 자연어 질의 실패 | Topic·Action 한정, 확실한 응답만 |

---

## 12. 평가 기준 자기점검

### 12.1 체크리스트

- [x] **서비스 완성도**: Tier 1 시연 골든패스 6분 흐름 명확
- [x] **비즈니스 가치**: §4.1의 4가지 차별화, 다른 조원과 중복 없음
- [x] **사용자 관점**: AE 김민수 페르소나 명확, 입력 부담 90% 감축
- [x] **아키텍처 설계**: ERP 게이트웨이로 결합도 낮춤, 컴포넌트 단위 모듈화
- [x] **기술 선택 적절성**: §5.3 정당성 매트릭스, 안티패턴 회피 검증
- [x] **코드 품질**: 작은 LWC 분리, Apex 인터페이스, Flow 시각화

### 12.2 안티패턴 회피 검증

| 안티패턴 | 본 시스템 | 회피 |
|---|---|---|
| 단순 카테고리 분기에 Prompt Builder | "환불/배송" 같은 yes/no는 없음, 항상 6+ 카테고리 + 자유텍스트 | ✅ |
| Apex로 Sales 표준 워크플로우 재구현 | Lead Convert·Stage 전이는 Flow 사용 | ✅ |
| 거대 LWC 단일 컴포넌트 | 카드별 LWC 분리 (RfqCard, OrderRiskCard 등 6개+) | ✅ |
| ERP/생산/품질 직접 구현 | Mock 인터페이스로 격리 | ✅ |
| Agentforce를 CRUD에 사용 | 조회·요약·자연어 횡단 질의에만 한정 | ✅ |

---

## Appendix A — 용어 사전

- **L2C (Lead-to-Cash)**: 잠재 고객 인입부터 매출 회수까지의 영업 사이클
- **AE (Account Executive)**: 거래처 담당 영업
- **RFQ (Request for Quote)**: 견적 요청
- **AR (Accounts Receivable)**: 미수금
- **MOQ (Minimum Order Quantity)**: 최소 주문 수량
- **Human-in-the-loop**: AI 자동화 + 사용자의 최종 검토·승인이 결합된 워크플로우 패턴

## Appendix B — 가정 및 제약

- 한도정밀(가칭)은 가상 회사. 실제 회사 데이터 사용 안 함.
- ERP/생산/품질 시스템은 Mock(Beeceptor)으로 시뮬레이션. 실제 시스템 연동 아님.
- Org는 기존 Agentforce DE Org "My_Org" 사용.
- Salesforce Sales Cloud + Agentforce + Prompt Builder 라이선스 사용.

---

**문서 끝**
