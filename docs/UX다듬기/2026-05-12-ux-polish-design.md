# Day 13 — UX 다듬기 6건 (Design Spec)

**작성**: 2026-05-12 (화)
**목표**: 시연 동영상 캡처 전 UX 6개 다듬기. Architecture 변경 없음 (D33).
**총 추정 시간**: ~3.5h
**의사결정**: D33 (표면만 다듬기, 5종 기술 라인/Action 5종/통합 narrative 유지)

---

## 1. 변경 매트릭스

| # | 영역 | 핵심 변경 | 시간 |
|---|---|---|---|
| 1 | 협상→수주 단계 안내 | StageGateService `'수주'` 분기 + GateResult.info 플래그 + LWC SLDS info 스타일 | 10분 |
| 2 | 납기일(EndDate) 표시 | 시드 백필 + Apex `dueLabel(endDate)` 헬퍼 + orderRiskCard 컬럼 + aeCockpit 위험 카드 배지 | 45분 |
| 3 | AI 응답 인라인 ID 링크 | AgentSynthesize Prompt 마커 규칙 + agentforceInputBar 파서 + NavigationMixin | 45분 |
| 4 | 공통 AI 로딩 메시지 | Custom Label `AI_Loading_Message` + 7 LWC 일괄 교체 | 30분 |
| 5 | 견적 게이트 (첨부 검사) | StageGateService.checkQuoteReadiness + ContentDocumentLink COUNT + Test 2 케이스 | 45분 |
| 6 | 챗봇 스타일 입력바 | agentforceInputBar HTML/CSS 만 — 말풍선·아바타·타이핑 점 | 45분 |

---

## 2. #1 — 협상→수주 안내 텍스트

### 변경

- `StageGateService.evaluateRules` 의 `'수주'` 분기를 신설(현재 빈 List 반환).
- `GateResult` 클래스에 `Boolean info` 플래그 4번째 인자 추가 (기본 false, backward compatible).
- `'수주'` 분기에서 1건 반환:

```apex
results.add(new GateResult(
    'info_only',
    '협상 완료시 [수주]로 전환하세요.',
    true,    // passed (안내일 뿐 차단 X)
    true     // info (LWC 가 안내 스타일로 렌더링)
));
```

- `stageGateChecklist` LWC: `result.info===true` 면 SLDS `slds-notify_alert slds-theme_info` 회색/파랑 안내 박스 스타일.

### 검증

- Anonymous Apex: `StageGateService.checkOppGate(oppId, '수주')` 호출 → 1건 info_only 반환 확인
- UI: 협상 단계 Opp 페이지에서 Path → '수주' 호버 시 안내 박스 표시

---

## 3. #2 — 납기일 (Order.EndDate)

### 시드 백필 정책

| 카테고리 | PoNumber 끝 | Production_Status | EndDate |
|---|---|---|---|
| 위험 5건 | '6' | InProgress | `today + 1~3일` (임박) |
| 대형지연 5건 | '9' | InProgress | `today - 1~5일` (OVERDUE) |
| 나머지 InProgress | 0~5 | InProgress | `EffectiveDate + 30일` |
| Done/Shipped | 모두 | Done/Shipped | `EffectiveDate + 30일` 또는 unchanged |
| Pending | 모두 | Pending | `EffectiveDate + 30일` |

### Apex 헬퍼

`AeCockpitService` 클래스 안에 `@TestVisible static String dueLabel(Date endDate)` 추가 (이미 riskyOrders DTO 빌드를 책임지는 위치). 다른 클래스가 필요하면 그때 분리.

```apex
public static String dueLabel(Date endDate) {
    if (endDate == null) return '';
    Integer days = Date.today().daysBetween(endDate);
    if (days < 0)  return '⚠ D+' + Math.abs(days) + ' 초과';
    if (days == 0) return '⏰ D-day';
    if (days <= 3) return '🔥 D-' + days;
    return 'D-' + days;
}
```

### UI

- **orderRiskCard 테이블**: 기존 컬럼 (Order/PoNumber/위험 점수/Production_Status) 다음에 "납기일" 컬럼 추가 — `<endDate>` 날짜 + `<dueLabel>` SLDS badge (overdue=red, ≤3=amber, 나머지=neutral).
- **aeCockpit 위험 Order 카드**: 각 행 우측에 같은 배지.
- AeCockpitService.fetchRiskyOrders SOQL 에 `EndDate` 추가, DTO 에 `endDate`, `dueLabel` 필드.

### 검증

- 시드 백필 후 verifyDay8 재실행 → 위험 5건 D-3 이내 / 대형지연 5건 OVERDUE / 정상 90건 D-7~D-30
- orderRiskCard / aeCockpit 새로고침 시 배지 색상 확인

---

## 4. #3 — AI 응답 인라인 ID 링크

### AgentSynthesize Prompt 마커 규칙

기존 응답 규칙 6개 다음에 7번째 규칙 추가:

> 7. 특정 레코드(Account/Order/Quote)를 언급할 때 이름 직후에 `{{id:18자ID}}` 토큰을 붙여라. ID 는 ActionResult JSON 의 accountId/orderId/quoteId/recordId 필드에서 가져와라. ID 없으면 토큰 생략.
>    - 예: `대성기공(주){{id:001xxxxxxxxxxxxxxx}} 의 미출고 Order 가 3건이에요.`
>    - 잘못된 예: `대성기공(주)의 미출고 Order` (ID 인용 안 됨)

길이 제한도 320자로 상향 (마커 오버헤드).

### LWC 파서

`agentforceInputBar.js`:

```js
parseInlineIds(message) {
    if (!message) return [{ text: '', recordId: null }];
    const re = /(\S+?)\{\{id:([a-zA-Z0-9]{15,18})\}\}/g;
    const segments = [];
    let lastIdx = 0, m;
    while ((m = re.exec(message)) !== null) {
        if (m.index > lastIdx) segments.push({ text: message.slice(lastIdx, m.index), recordId: null });
        segments.push({ text: m[1], recordId: m[2] });
        lastIdx = re.lastIndex;
    }
    if (lastIdx < message.length) segments.push({ text: message.slice(lastIdx), recordId: null });
    return segments;
}
```

HTML 템플릿:

```html
<template for:each={segments} for:item="s">
    <template lwc:if={s.recordId}>
        <a href="javascript:void(0)" data-id={s.recordId} onclick={handleNav}>{s.text}</a>
    </template>
    <template lwc:else>{s.text}</template>
</template>
```

`handleNav` → NavigationMixin.Navigate with recordPage type. 파싱 실패 또는 ID 누락 시 원문 그대로 (graceful).

### 검증

- E2E: "대성기공(주) 물건 나갔나요?" → 응답에서 "대성기공(주)" 가 underline 링크로 렌더 → 클릭 시 Account 페이지 이동
- Synthesize 가 마커 안 넣은 경우 (LLM 무시) → 원문 그대로 평문 표시 (회귀 없음)

---

## 5. #4 — 공통 AI 로딩 메시지

### Custom Label 신설

```xml
<labels>
    <fullName>AI_Loading_Message</fullName>
    <language>ko</language>
    <protected>false</protected>
    <shortDescription>AI 로딩 공통 메시지</shortDescription>
    <value>잠시만 기다려 주세요... AI 가 답변을 작성 중이에요</value>
</labels>
```

### LWC 일괄 교체

대상 (7개):
- `agentforceInputBar`
- `businessLicenseUpload`
- `oppInsightCard`
- `orderRiskCard`
- `quoteBuilder` (재견적/이메일 발송 액션)
- `phoneLeadIntake`
- `visitLeadIntake`

각 LWC 변경:

```js
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';
// ...
label = { aiLoading: AI_LOADING };
```

```html
<lightning-spinner alternative-text={label.aiLoading} ...></lightning-spinner>
<p class="loading-text" lwc:if={isLoading}>{label.aiLoading}</p>
```

### 검증

- 각 LWC 에서 AI 호출 트리거 → 스피너 + 통일된 한국어 문구 표시

---

## 6. #5 — 견적 단계 게이트 (첨부 검사)

### 룰 추가

`StageGateService.checkQuoteReadiness(quoteId)`:

```apex
Integer attCount = [
    SELECT COUNT()
    FROM ContentDocumentLink
    WHERE LinkedEntityId = :quoteId
];
if (attCount == 0) {
    failures.add('견적 첨부 파일이 1개 이상 필요합니다 (견적서 PDF 생성 또는 직접 업로드)');
}
```

### 시연 동선 효과

기존 동선: quoteBuilder 작성 → 라인 추가 → 단계 전환 시도 → ✅ (게이트 통과)
변경 동선: quoteBuilder 작성 → 라인 추가 → 단계 전환 시도 → **❌ "첨부 1개 이상"** → [PDF 생성] 버튼 → 다시 전환 → ✅

→ 평가자에게 "AE 가 PDF 생성 안 하고 발송하는 실수 차단" narrative.

### Test

`StageGateServiceTest` 에 2 케이스 추가:
- `testQuoteReadiness_noAttachment_fails`
- `testQuoteReadiness_withAttachment_passes` (Test 데이터: ContentVersion + ContentDocumentLink 인서트)

### 검증

- Anonymous Apex 회귀: 시드 Quote 중 첨부 없는 것 골라 `checkOppGate(oppId, '견적 발송')` 호출 → failures 에 새 메시지 포함

---

## 7. #6 — 챗봇 스타일 입력바

### HTML 재구성

`agentforceInputBar.html` 전면 개편 (Apex/JS 핵심 로직은 그대로):

```html
<lightning-card>
    <div class="chatbot">
        <header class="chatbot__header">
            <span class="bot-icon">🤖</span>
            <span class="bot-title">세일즈 도우미</span>
        </header>

        <div class="chatbot__log" lwc:ref="log">
            <template for:each={messages} for:item="m">
                <div key={m.id} class={m.cssClass}>
                    <div class="avatar">{m.avatar}</div>
                    <div class="bubble">
                        <!-- inline ID 파싱 결과 segments 렌더링 (#3) -->
                    </div>
                </div>
            </template>
            <template lwc:if={isLoading}>
                <div class="msg msg-ai typing">
                    <div class="avatar">🤖</div>
                    <div class="bubble"><span class="dot"></span><span class="dot"></span><span class="dot"></span></div>
                </div>
            </template>
        </div>

        <div class="chatbot__input">
            <lightning-input ... onkeyup={handleEnter}></lightning-input>
            <lightning-button-icon icon-name="utility:send" onclick={handleSend}></lightning-button-icon>
        </div>
    </div>
</lightning-card>
```

### 메시지 누적

- `messages = []` 상태 — user 메시지 + AI 응답 누적
- 새 메시지 추가 시 `setTimeout(() => log.scrollTop = log.scrollHeight, 0)` 자동 스크롤
- 페이지 새로고침 시 초기화 (이력 보존 X)

### 스타일

- user 메시지: 우측 정렬, 회색 버블
- AI action 응답: 좌측 정렬, 파랑 버블 + 🤖 아바타
- AI llm_fallback: 좌측 정렬, 보라 버블 + 🤖 아바타 (기존 보라 LLM 배지 유지)
- 타이핑 점: 0.4s 간격 bouncing animation (`@keyframes typing-bounce`)
- 채팅창 높이: 400px 고정, 스크롤
- 입력창: SLDS 표준 textbox + 우측 send 버튼

### 검증

- 자유 질문 3건 연속 입력 → 모두 누적, 스크롤 자동
- 로딩 중 타이핑 점 애니메이션 동작
- ID 링크 (#3) 와 통합 — 응답 버블 안의 회사명 클릭 가능

---

## 8. 위험 / 비고

- **#3 LLM 마커 무시 위험**: GPT41Mini 가 `{{id:...}}` 토큰 규칙을 모를 수 있음 → 파싱 실패 시 원문 그대로 (graceful). 시연 시 1~2회 실 호출로 검증.
- **#2 시드 백필**: 기존 시드의 EndDate 가 이미 채워져 있으면 update만, null 이면 insert. `scripts/apex/backfillOrderDueDates.apex` 신설.
- **#5 게이트 강화 후 회귀**: 기존 Apex Test 중 Quote 단계 전환 검증하는 테스트들이 첨부 없으면 깨질 수 있음 → 테스트 setup 에 ContentVersion 인서트 추가 필요.
- **#6 메시지 누적**: 메모리 누수 방지 — 최대 50개로 capping (오래된 메시지 자동 제거).

---

## 9. 산출물 카탈로그 (delta)

**신규**:
- `force-app/main/default/labels/CustomLabels.labels-meta.xml` 에 `AI_Loading_Message` 추가 (파일 신설 또는 기존 추가)
- `scripts/apex/backfillOrderDueDates.apex` (Order.EndDate 일회성 백필; `seedData.apex` 는 건드리지 않음 — 시드 재실행 무관한 delta)

**수정**:
- `force-app/main/default/classes/opp/StageGateService.cls` (게이트 룰 2건 추가: `'수주'` info_only + `checkQuoteReadiness` 첨부 검사)
- `force-app/main/default/classes/opp/StageGateServiceTest.cls` (Test 4 추가: 협상→수주 + 첨부 0/1+)
- `force-app/main/default/classes/cockpit/AeCockpitService.cls` (riskyOrders DTO 에 endDate/dueLabel + `dueLabel(Date)` static 헬퍼)
- `force-app/main/default/genAiPromptTemplates/AgentSynthesize.genAiPromptTemplate-meta.xml` (마커 규칙 7번 추가 + 길이 320자)
- `force-app/main/default/lwc/agentforceInputBar/*.html/.css/.js` (챗봇 스타일 + ID 파서)
- `force-app/main/default/lwc/orderRiskCard/*.html/.js` (납기일 컬럼)
- `force-app/main/default/lwc/aeCockpit/*.html` (위험 카드 배지)
- `force-app/main/default/lwc/stageGateChecklist/*.html/.css` (info 스타일)
- 7 LWC (loading 텍스트 통일)

**예상 PASS 카운트**: 319 → ~325 (+6 신규 Test)

---

## 10. 의사결정 D33

> **D33 (2026-05-12) — UX 다듬기 6건은 architecture 변경 없이 표면만**. 5종 기술 라인 / 5 Action / 통합 L2C narrative 유지. 추가 메타 ≤ 신규 3건(Custom Label / 신규 Apex 0건 / 신규 LWC 0건). 시드 데이터의 EndDate 만 백필. 평가자 narrative: "core architecture 가 안정되어 시연 직전 UX 다듬기를 빠르게 반복 가능".
