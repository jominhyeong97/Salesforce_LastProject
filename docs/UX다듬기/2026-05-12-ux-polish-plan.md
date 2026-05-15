# Day 13 — UX 다듬기 6건 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 시연 동영상 캡처 전에 6개 UX 다듬기 — architecture 변경 없이 표면만, ~3.5h 안에 끝.

**Architecture:** D33 (스펙 §10). 신규 Apex/LWC 0건, 신규 메타 ≤ 2건(Custom Label + 백필 스크립트). 모든 변경은 기존 클래스/LWC 의 메소드·HTML·CSS 확장.

**Tech Stack:** Salesforce DX, Apex (Test.isRunningTest mock 패턴), Lightning Web Components, GenAiPromptTemplate. SF CLI 2.133.4. Target org: `My_Org`.

**Project conventions (HANDOFF §1, §6 참조):**
- 배포: `sf project deploy start --target-org My_Org`
- 테스트: `sf apex run test --tests <Class> --target-org My_Org --code-coverage --result-format human`
- git 미초기화 — "commit" step 대신 deploy + apex run test 검증으로 대체.
- API value 한국어 (StageName='발굴' 등) — assertion 도 한국어로.

---

## File Structure

신규 파일 (2):
- `force-app/main/default/labels/CustomLabels.labels-meta.xml` — 또는 기존 파일에 `AI_Loading_Message` Custom Label 추가
- `scripts/apex/backfillOrderDueDates.apex` — 시드 100건 Order.EndDate 일회성 백필

수정 파일 (12):
- `force-app/main/default/lwc/stageGateChecklist/stageGateChecklist.html` (#1)
- `force-app/main/default/lwc/stageGateChecklist/stageGateChecklist.js` (#1)
- `force-app/main/default/classes/cockpit/AeCockpitService.cls` (#2)
- `force-app/main/default/classes/cockpit/AeCockpitService_Test.cls` (#2)
- `force-app/main/default/lwc/orderRiskCard/orderRiskCard.html` (#2)
- `force-app/main/default/lwc/orderRiskCard/orderRiskCard.js` (#2)
- `force-app/main/default/lwc/aeCockpit/aeCockpit.html` (#2)
- `force-app/main/default/genAiPromptTemplates/AgentSynthesize.genAiPromptTemplate-meta.xml` (#3)
- `force-app/main/default/lwc/agentforceInputBar/agentforceInputBar.js` (#3, #6)
- `force-app/main/default/lwc/agentforceInputBar/agentforceInputBar.html` (#6)
- `force-app/main/default/lwc/agentforceInputBar/agentforceInputBar.css` (#6)
- `force-app/main/default/classes/opp/StageGateService.cls` (#5)
- `force-app/main/default/classes/opp/StageGateServiceTest.cls` (#5)
- 7 LWC for `AI_Loading_Message` 통일 (#4)

---

## Task 1: 협상→수주 안내 텍스트 (LWC-only)

**Files:**
- Modify: `force-app/main/default/lwc/stageGateChecklist/stageGateChecklist.html` (line 51-53 `<template lwc:else>`)
- Modify: `force-app/main/default/lwc/stageGateChecklist/stageGateChecklist.js` (신규 getter `isPreWonStage`, `isTerminalStage`)

**컨텍스트**:
- 현재 LWC 41~53줄: `result.rules` 비었으면 "이 단계에 게이트 룰이 정의되지 않았습니다." 표시.
- 협상→수주는 룰 0 (Service `evaluateRules` 에 매핑 없음). 사용자는 협상 단계에서 "협상 완료시 [수주]로 전환하세요" 만 보고 싶음.
- 수주/실주 terminal 단계는 `nextStage === currentStage` (Service line 148) — terminal 분기 따로.

- [ ] **Step 1.1: stageGateChecklist.js 에 getter 2개 추가**

`force-app/main/default/lwc/stageGateChecklist/stageGateChecklist.js` 의 `get` 섹션에 추가 (기존 `nextBadgeVariant`/`hasResult` 옆):

```js
get isPreWonStage() {
    return this.result?.currentStage === '협상' && this.result?.nextStage === '수주';
}

get isTerminalStage() {
    return this.result && this.result.currentStage === this.result.nextStage;
}
```

- [ ] **Step 1.2: stageGateChecklist.html else 블록을 3분기로 교체**

`stageGateChecklist.html` 51~53줄 교체:

```html
<template lwc:else>
    <template lwc:if={isPreWonStage}>
        <div class="slds-notify slds-notify_alert slds-theme_info slds-p-around_small">
            💡 협상 완료시 [수주]로 전환하세요.
        </div>
    </template>
    <template lwc:elseif={isTerminalStage}>
        <div class="slds-text-color_weak">최종 단계입니다.</div>
    </template>
    <template lwc:else>
        <div class="slds-text-color_weak">이 단계에 게이트 룰이 정의되지 않았습니다.</div>
    </template>
</template>
```

- [ ] **Step 1.3: 배포 + 시연 검증**

```bash
sf project deploy start --source-dir force-app/main/default/lwc/stageGateChecklist --target-org My_Org
```

Expected: `Succeeded`, 2 components Changed.

UI 검증:
1. Opp 'IB Opp' (또는 임의 협상 단계 Opp) 의 StageName 을 '협상' 으로 update → `stageGateChecklist` 영역에 "💡 협상 완료시 [수주]로 전환하세요." info 박스 표시.
2. StageName='수주' update → "최종 단계입니다." 표시.

Anonymous Apex (확인용, Opp 1건 골라):
```apex
Opportunity o = [SELECT Id, StageName FROM Opportunity WHERE StageName != '수주' LIMIT 1];
o.StageName = '협상';
update o;
System.debug('=== 변경 완료. Opp Id: ' + o.Id);
```

---

## Task 2: 납기일(Order.EndDate) 표시

**Files:**
- Create: `scripts/apex/backfillOrderDueDates.apex`
- Modify: `force-app/main/default/classes/cockpit/AeCockpitService.cls` (RiskyOrderRow DTO 에 `endDate`, `dueLabel`; `fetchRiskyOrders` SOQL + DTO 매핑; 신규 static `dueLabel(Date)`)
- Modify: `force-app/main/default/classes/cockpit/AeCockpitService_Test.cls` (testDueLabel + risky order EndDate 검증)
- Modify: `force-app/main/default/lwc/orderRiskCard/orderRiskCard.html` (납기일 컬럼)
- Modify: `force-app/main/default/lwc/orderRiskCard/orderRiskCard.js` (DTO 매핑 변환)
- Modify: `force-app/main/default/lwc/aeCockpit/aeCockpit.html` (위험 카드 행 우측 dueLabel 배지)

### Step 2A: AeCockpitService.dueLabel 헬퍼 + DTO 확장

- [ ] **Step 2.1: AeCockpitService_Test 에 dueLabel 단위 테스트 추가 (TDD)**

`AeCockpitService_Test.cls` 끝에 추가:

```apex
@IsTest
static void testDueLabel_returnsCorrectFormat() {
    Date today = Date.today();
    System.assertEquals('', AeCockpitService.dueLabel(null));
    System.assert(AeCockpitService.dueLabel(today.addDays(-3)).contains('초과'),
        'overdue label expected');
    System.assert(AeCockpitService.dueLabel(today.addDays(-3)).contains('D+3'));
    System.assertEquals('⏰ D-day', AeCockpitService.dueLabel(today));
    System.assertEquals('🔥 D-1', AeCockpitService.dueLabel(today.addDays(1)));
    System.assertEquals('🔥 D-3', AeCockpitService.dueLabel(today.addDays(3)));
    System.assertEquals('D-7', AeCockpitService.dueLabel(today.addDays(7)));
}
```

- [ ] **Step 2.2: 테스트 실행 — 실패 확인**

```bash
sf apex run test --tests AeCockpitService_Test.testDueLabel_returnsCorrectFormat --target-org My_Org --result-format human
```

Expected: FAIL ("Method does not exist or incorrect signature: dueLabel").

- [ ] **Step 2.3: AeCockpitService.cls 에 dueLabel + DTO 확장**

`AeCockpitService.cls` 의 `nzInt` 헬퍼 바로 위에 추가:

```apex
@TestVisible
public static String dueLabel(Date endDate) {
    if (endDate == null) return '';
    Integer days = Date.today().daysBetween(endDate);
    if (days < 0)  return '⚠ D+' + Math.abs(days) + ' 초과';
    if (days == 0) return '⏰ D-day';
    if (days <= 3) return '🔥 D-' + days;
    return 'D-' + days;
}
```

`RiskyOrderRow` DTO 에 2 필드 추가 (line 193~201):

```apex
public class RiskyOrderRow {
    @AuraEnabled public Id orderId;
    @AuraEnabled public String orderName;
    @AuraEnabled public String poNumber;
    @AuraEnabled public String accountName;
    @AuraEnabled public String productionStatus;
    @AuraEnabled public Integer riskScore;
    @AuraEnabled public DateTime lastErpSyncAt;
    @AuraEnabled public Date endDate;        // 신규
    @AuraEnabled public String dueLabel;     // 신규
}
```

`fetchRiskyOrders` SOQL 에 `EndDate` 추가, DTO 매핑에 `r.endDate` + `r.dueLabel` 추가 (line 107~123):

```apex
private static List<RiskyOrderRow> fetchRiskyOrders() {
    List<RiskyOrderRow> out = new List<RiskyOrderRow>();
    for (Order o : [
        SELECT Id, Name, PoNumber, Production_Status__c, Delivery_Risk_Score__c,
               Last_ErpSync_At__c, EndDate, Account.Name
        FROM Order
        WHERE Delivery_Risk_Score__c >= 70
        ORDER BY Delivery_Risk_Score__c DESC
        LIMIT :ROW_LIMIT
    ]) {
        RiskyOrderRow r = new RiskyOrderRow();
        r.orderId          = o.Id;
        r.orderName        = o.Name;
        r.poNumber         = o.PoNumber;
        r.accountName      = (o.Account != null) ? o.Account.Name : '';
        r.productionStatus = o.Production_Status__c;
        r.riskScore        = nzInt(o.Delivery_Risk_Score__c);
        r.lastErpSyncAt    = o.Last_ErpSync_At__c;
        r.endDate          = o.EndDate;
        r.dueLabel         = dueLabel(o.EndDate);
        out.add(r);
    }
    return out;
}
```

- [ ] **Step 2.4: 배포 + 테스트 통과 확인**

```bash
sf project deploy start --source-dir force-app/main/default/classes/cockpit --target-org My_Org --ignore-warnings --test-level RunSpecifiedTests --tests AeCockpitService_Test
```

Expected: `Succeeded`, all `AeCockpitService_Test` PASS (기존 6 + 신규 1 = 7).

### Step 2B: 시드 백필 (Order.EndDate)

- [ ] **Step 2.5: backfillOrderDueDates.apex 작성**

`scripts/apex/backfillOrderDueDates.apex`:

```apex
// Order.EndDate 백필 — 시연용 결정적 분포
// 위험 5건 (PoNumber 끝 6 + InProgress): today + 1~3일 (임박)
// 대형지연 5건 (끝 9 + InProgress): today - 1~5일 (OVERDUE)
// 나머지: EffectiveDate + 30일

List<Order> orders = [
    SELECT Id, PoNumber, Production_Status__c, EffectiveDate, EndDate
    FROM Order
    WHERE PoNumber LIKE 'PO-2026-%'
];

Date today = Date.today();
Integer riskIdx = 0, longIdx = 0;
List<Order> toUpdate = new List<Order>();

for (Order o : orders) {
    if (o.PoNumber == null) continue;
    String last = o.PoNumber.right(1);
    Boolean isInProg = o.Production_Status__c == 'InProgress';

    Date newDate;
    if (last == '6' && isInProg) {
        // 임박 (D-1, D-2, D-3)
        newDate = today.addDays((riskIdx % 3) + 1);
        riskIdx++;
    } else if (last == '9' && isInProg) {
        // OVERDUE (D+1 ~ D+5)
        newDate = today.addDays(-1 * ((longIdx % 5) + 1));
        longIdx++;
    } else if (o.EffectiveDate != null) {
        newDate = o.EffectiveDate.addDays(30);
    } else {
        newDate = today.addDays(30);
    }
    o.EndDate = newDate;
    toUpdate.add(o);
}

update toUpdate;
System.debug('=== Updated EndDate on ' + toUpdate.size() + ' Orders. risk=' + riskIdx + ' overdue=' + longIdx);

// 검증
Integer overdue = 0, imminent = 0, safe = 0;
for (Order o : [SELECT EndDate FROM Order WHERE PoNumber LIKE 'PO-2026-%' AND EndDate != null]) {
    Integer days = Date.today().daysBetween(o.EndDate);
    if (days < 0) overdue++;
    else if (days <= 3) imminent++;
    else safe++;
}
System.debug('=== overdue: ' + overdue + ', imminent: ' + imminent + ', safe: ' + safe);
```

- [ ] **Step 2.6: 백필 실행 + 분포 확인**

```bash
sf apex run --file scripts/apex/backfillOrderDueDates.apex --target-org My_Org
```

Expected debug: `Updated EndDate on 100 Orders. risk=5 overdue=5` + `overdue: 5, imminent: 5, safe: 90`.

### Step 2C: orderRiskCard LWC 컬럼 추가

- [ ] **Step 2.7: orderRiskCard.js 변환에 endDate/dueLabel 매핑 추가**

`force-app/main/default/lwc/orderRiskCard/orderRiskCard.js` 의 risky orders 변환 부분 — `getRiskView` 또는 `syncOrders` 결과를 row 객체로 변환하는 코드에서 endDate/dueLabel 필드를 보존하도록 추가. 정확한 위치는 기존 매핑 함수 내부:

```js
return outs.map(o => ({
    orderId: o.orderId,
    orderName: o.orderName,
    poNumber: o.poNumber,
    accountName: o.accountName,
    productionStatus: o.productionStatus,
    riskScore: o.riskScore,
    riskClass: this.getRiskClass(o.riskScore),
    lastErpSyncAt: o.lastErpSyncAt,
    endDate: o.endDate,           // 신규
    dueLabel: o.dueLabel,         // 신규
    dueClass: this.getDueClass(o.dueLabel)  // 신규
}));
```

신규 헬퍼 `getDueClass`:

```js
getDueClass(label) {
    if (!label) return 'slds-badge';
    if (label.includes('초과')) return 'slds-badge slds-theme_error';
    if (label.includes('D-day') || label.includes('D-1') || label.includes('D-2') || label.includes('D-3')) {
        return 'slds-badge slds-theme_warning';
    }
    return 'slds-badge';
}
```

(주의: 기존 row mapping 함수 시그니처 — `getRiskView` 응답 형태는 `OrderErpSyncService.OrderRiskView` 임. 거기에 endDate 도 추가 필요. → Step 2.8 참고.)

- [ ] **Step 2.8: OrderErpSyncService.OrderRiskView 에 endDate/dueLabel 추가**

`force-app/main/default/classes/order/OrderErpSyncService.cls` 의 `OrderRiskView` 또는 `getRiskView` SOQL — Open Order list 에 EndDate 필드 SOQL 추가 + DTO 필드 2개 + `dueLabel = AeCockpitService.dueLabel(o.EndDate)` 호출 추가. (정확한 줄 위치는 파일 안에서 OrderRiskView DTO 클래스 검색)

Expected 변경: SOQL `SELECT EndDate, ...`, DTO 필드 `@AuraEnabled public Date endDate; @AuraEnabled public String dueLabel;`, 매핑 라인 추가.

- [ ] **Step 2.9: orderRiskCard.html 에 납기일 컬럼**

기존 위험 점수 컬럼 다음에 추가 (테이블 행 안):

```html
<td>
    <lightning-formatted-date-time value={row.endDate} year="numeric" month="2-digit" day="2-digit"></lightning-formatted-date-time>
    <template lwc:if={row.dueLabel}>
        <span class={row.dueClass} style="margin-left:0.4rem;">{row.dueLabel}</span>
    </template>
</td>
```

테이블 헤더에도 `<th>납기일</th>` 추가.

- [ ] **Step 2.10: aeCockpit.html 위험 Order 카드 행에 배지**

`aeCockpit.html` 에서 `riskyOrders` 반복 영역 — 각 row 의 위험 점수 옆 또는 우측 끝에:

```html
<template lwc:if={row.dueLabel}>
    <span class="slds-badge slds-m-left_x-small">{row.dueLabel}</span>
</template>
```

(aeCockpit.js 매핑이 raw DTO 그대로 전달하는지 변환하는지 확인 후 매핑 보존)

- [ ] **Step 2.11: 배포 + UI 시연 검증**

```bash
sf project deploy start --source-dir force-app/main/default/lwc/orderRiskCard --source-dir force-app/main/default/lwc/aeCockpit --source-dir force-app/main/default/classes/order --target-org My_Org --ignore-warnings --test-level RunLocalTests
```

Expected: `Succeeded`, all tests pass (319+).

UI 검증:
1. Order ORD-1009 (PoNumber 끝 9, 대형지연) 페이지 → orderRiskCard 에 "⚠ D+N 초과" 빨간 배지.
2. Home → aeCockpit 위험 Order 카드에 5개 행, 각 행에 D-N / D+N 배지.

---

## Task 3: AgentSynthesize Prompt 마커 규칙 추가

**Files:**
- Modify: `force-app/main/default/genAiPromptTemplates/AgentSynthesize.genAiPromptTemplate-meta.xml` (Draft 로 strip activeVersionIdentifier → 규칙 추가 → 2단계 활성화)

### Step 3A: Prompt 본문 업데이트 + 1차 Draft 재배포

- [ ] **Step 3.1: AgentSynthesize.genAiPromptTemplate-meta.xml 본문 수정**

기존 6번 규칙 다음에 7번 추가, 길이 제한 300→320 으로 변경:

```xml
6. 한국 영업 정서 — 회사명에 &quot;(주)&quot; 등 접미사 그대로 인용 가능.
7. 특정 레코드(Account/Order/Quote)를 언급할 때 이름 직후에 {{id:18자ID}} 토큰을 붙여라. ID 는 ActionResult JSON 의 accountId / orderId / quoteId / recordId / candidates[].productId 등에서 가져온다. ID 가 JSON 에 없으면 토큰 생략.
   - 올바른 예: &quot;대성기공(주){{id:001xxxxxxxxxxxxxxx}} 의 미출고 Order 가 3건이에요.&quot;
   - 잘못된 예: &quot;대성기공(주) 의 미출고 Order&quot; (JSON 에 accountId 있는데 토큰 생략)
8. 길이 제한: 최대 320자 이내.
```

기존 7번 길이 제한은 8번으로 번호 이동.

또한 마커 사용 예시를 == 예시 == 섹션에 1건 추가:

```
질의: &quot;납기 위험 어떤 게 있어?&quot;
도구: GetOrderAtRisk
결과: {&quot;riskCount&quot;:3,&quot;detailsJson&quot;:&quot;[{&apos;orderId&apos;:&apos;801xxxxxxxxxxxxxxx&apos;,&apos;orderName&apos;:&apos;PO-2026-0079&apos;,&apos;accountName&apos;:&apos;진성정밀(주)&apos;}]&quot;}
→ 응답: &quot;현재 납기 위험 Order 3건이에요. 진성정밀(주) 의 PO-2026-0079{{id:801xxxxxxxxxxxxxxx}} 가 가장 위험점수 높아 우선 점검 추천드려요.&quot;
```

(versionIdentifier / activeVersionIdentifier 변경은 Step 3.4 에서)

- [ ] **Step 3.2: activeVersionIdentifier 일시 제거 (Draft 신규 버전 생성)**

같은 파일에서:
- `<activeVersionIdentifier>...</activeVersionIdentifier>` 줄 삭제
- `<status>Published</status>` → `<status>Draft</status>`
- `<versionIdentifier>...</versionIdentifier>` 줄 삭제

(SF가 새 versionIdentifier 자동 생성하도록)

- [ ] **Step 3.3: Draft 1차 배포**

```bash
sf project deploy start --source-dir force-app/main/default/genAiPromptTemplates/AgentSynthesize.genAiPromptTemplate-meta.xml --target-org My_Org
```

Expected: `Succeeded`, 1 component Changed.

- [ ] **Step 3.4: retrieve 로 신규 versionIdentifier 확보**

```bash
sf project retrieve start --metadata "GenAiPromptTemplate:AgentSynthesize" --target-org My_Org
```

Expected: 파일이 다시 변경됨. 새 `<versionIdentifier>....=_2</versionIdentifier>` (또는 _3 등) 등장.

- [ ] **Step 3.5: activeVersionIdentifier + Published 명시 후 재배포**

retrieve 된 versionIdentifier 값 (예: `KqXYZ...=_2`) 을 메타에 추가:
- 최상단에 `<activeVersionIdentifier>KqXYZ...=_2</activeVersionIdentifier>` 추가
- `<status>Draft</status>` → `<status>Published</status>`

```bash
sf project deploy start --source-dir force-app/main/default/genAiPromptTemplates/AgentSynthesize.genAiPromptTemplate-meta.xml --target-org My_Org
```

Expected: `Succeeded`.

- [ ] **Step 3.6: E2E 실 LLM 검증 — 마커 삽입 확인**

Anonymous Apex (1건 호출):

```apex
AgentforceInputBarService.AgentResponse r = AgentforceInputBarService.ask('납기 위험 어떤 게 있어?', null);
System.debug('=== message: ' + r.message);
// {{id:801xxx...}} 토큰 포함 여부 확인
System.assert(r.message.contains('{{id:'), 'expected inline id marker, got: ' + r.message);
```

LLM 응답이 토큰 무시할 경우 — Step 3.1 의 프롬프트 규칙을 강화하거나, 단순 graceful (LWC 가 파싱 실패 시 평문 그대로).

(주의: LLM 답변 변동성 — 3건 이상 시도해 평균적으로 마커 삽입 확인.)

---

## Task 4: 공통 AI 로딩 메시지

**Files:**
- Create or Modify: `force-app/main/default/labels/CustomLabels.labels-meta.xml`
- Modify: 7 LWC (`agentforceInputBar`, `businessLicenseUpload`, `oppInsightCard`, `orderRiskCard`, `quoteBuilder`, `phoneLeadIntake`, `visitLeadIntake`)

- [ ] **Step 4.1: CustomLabels.labels-meta.xml 확인 및 신규 라벨 추가**

```bash
ls force-app/main/default/labels/
```

기존 파일 있으면 추가, 없으면 신설:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomLabels xmlns="http://soap.sforce.com/2006/04/metadata">
    <labels>
        <fullName>AI_Loading_Message</fullName>
        <language>ko</language>
        <protected>false</protected>
        <shortDescription>AI 로딩 공통 메시지</shortDescription>
        <value>잠시만 기다려 주세요... AI가 답변을 작성 중이에요</value>
    </labels>
    <!-- 기존 라벨들 -->
</CustomLabels>
```

(기존 라벨 `Quote_Tracking_Base_URL` 있으면 보존)

- [ ] **Step 4.2: Custom Label 배포**

```bash
sf project deploy start --source-dir force-app/main/default/labels --target-org My_Org
```

Expected: `Succeeded`, 1 component Changed/Created.

- [ ] **Step 4.3: 7 LWC 에 import + 적용**

각 LWC 의 `.js` 파일에:

```js
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';
// ...
label = { aiLoading: AI_LOADING };
// 또는 class field 로
labels = { aiLoading: AI_LOADING };
```

각 LWC 의 `.html` 파일에서 기존 spinner / loading 텍스트 부분:

```html
<lightning-spinner alternative-text={labels.aiLoading} size="small"></lightning-spinner>
<!-- 또는 -->
<p class="loading-text" lwc:if={loading}>{labels.aiLoading}</p>
```

대상 LWC 별 변경 위치 (각 LWC 안에서 `lightning-spinner` 또는 `loading` 텍스트 검색):
- `agentforceInputBar.html` — `lightning-spinner alternative-text="로딩 중..."` 류 발견 시 교체. ⚠️ Task 6 에서 챗봇 스타일 재작성하므로 Task 6 이후로 미뤄도 됨. **순서 권장: Task 4 의 agentforceInputBar 변경은 Task 6 이후로**.
- `businessLicenseUpload` — OCR 호출 시 스피너
- `oppInsightCard` — AI Insight 호출 시 스피너
- `orderRiskCard` — ERP 동기화 / 사전 통보 메일 호출 시 스피너
- `quoteBuilder` — 재견적/이메일 발송 호출 시 스피너 (정확 위치는 .html grep)
- `phoneLeadIntake` — AI 추출 호출 시 스피너
- `visitLeadIntake` — AI 추출 호출 시 스피너

- [ ] **Step 4.4: 배포**

```bash
sf project deploy start --source-dir force-app/main/default/lwc --target-org My_Org --ignore-warnings
```

Expected: `Succeeded`.

- [ ] **Step 4.5: UI 검증**

각 LWC 의 AI 호출 동작 트리거 → 스피너 영역에 "잠시만 기다려 주세요... AI가 답변을 작성 중이에요" 통일 표시 확인 (최소 3개 LWC 샘플).

---

## Task 5: 견적 단계 게이트 — 첨부 검사

**Files:**
- Modify: `force-app/main/default/classes/opp/StageGateService.cls` (`checkQuoteReadiness` 확장)
- Modify: `force-app/main/default/classes/opp/StageGateServiceTest.cls` (Test 2 추가)

- [ ] **Step 5.1: StageGateServiceTest 에 신규 케이스 2건 (TDD)**

`StageGateServiceTest.cls` 끝에 추가:

```apex
@IsTest
static void testQuoteReadiness_noAttachment_addsFailure() {
    // setup — 사업자번호 ok Account + Opp + Quote + Line (첨부 0)
    Account a = new Account(Name='AttTest', Business_Number__c='100-00-00009');
    insert a;
    Opportunity o = new Opportunity(
        Name='AT Opp', AccountId=a.Id,
        StageName='견적 작성', CloseDate=Date.today().addDays(30)
    );
    insert o;

    Pricebook2 std = new Pricebook2(Id = Test.getStandardPricebookId());
    Quote q = new Quote(
        Name='AT-Q', OpportunityId=o.Id, Status='초안',
        ExpirationDate=Date.today().addDays(14)
    );
    insert q;
    // line
    Product2 p = new Product2(Name='AT P', ProductCode='ATP-001', IsActive=true);
    insert p;
    PricebookEntry pbe = new PricebookEntry(
        Pricebook2Id=Test.getStandardPricebookId(), Product2Id=p.Id,
        UnitPrice=1000, IsActive=true
    );
    insert pbe;
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId=q.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=1000
    );
    insert qli;

    Test.startTest();
    StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);
    Test.stopTest();

    System.assertEquals('견적 작성', r.currentStage);
    System.assertEquals('견적 발송', r.nextStage);

    Boolean foundAttRule = false;
    Boolean attRuleSatisfied = true;
    for (StageGateService.GateRule g : r.rules) {
        if (g.label != null && g.label.contains('첨부')) {
            foundAttRule = true;
            attRuleSatisfied = g.satisfied;
        }
    }
    System.assert(foundAttRule, '첨부 룰이 추가되어 있어야 함');
    System.assertEquals(false, attRuleSatisfied, '첨부 0건 시 satisfied=false');
}

@IsTest
static void testQuoteReadiness_withAttachment_passes() {
    Account a = new Account(Name='AttTest2', Business_Number__c='100-00-00009');
    insert a;
    Opportunity o = new Opportunity(
        Name='AT2 Opp', AccountId=a.Id,
        StageName='견적 작성', CloseDate=Date.today().addDays(30)
    );
    insert o;
    Quote q = new Quote(
        Name='AT2-Q', OpportunityId=o.Id, Status='초안',
        ExpirationDate=Date.today().addDays(14)
    );
    insert q;
    Product2 p = new Product2(Name='AT2 P', ProductCode='ATP2-001', IsActive=true);
    insert p;
    PricebookEntry pbe = new PricebookEntry(
        Pricebook2Id=Test.getStandardPricebookId(), Product2Id=p.Id,
        UnitPrice=2000, IsActive=true
    );
    insert pbe;
    QuoteLineItem qli = new QuoteLineItem(
        QuoteId=q.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=2000
    );
    insert qli;

    // 첨부 1건 추가
    ContentVersion cv = new ContentVersion(
        Title='Test Quote Attachment', PathOnClient='att.pdf',
        VersionData=Blob.valueOf('dummy pdf'), IsMajorVersion=true
    );
    insert cv;
    Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    ContentDocumentLink cdl = new ContentDocumentLink(
        LinkedEntityId=q.Id, ContentDocumentId=cdId, ShareType='V'
    );
    insert cdl;

    Test.startTest();
    StageGateService.GateResult r = StageGateService.checkOppGate(o.Id);
    Test.stopTest();

    Boolean attRuleSatisfied = false;
    for (StageGateService.GateRule g : r.rules) {
        if (g.label != null && g.label.contains('첨부')) {
            attRuleSatisfied = g.satisfied;
        }
    }
    System.assertEquals(true, attRuleSatisfied, '첨부 1건 시 satisfied=true');
}
```

- [ ] **Step 5.2: 테스트 실행 — 실패 확인**

```bash
sf apex run test --tests StageGateServiceTest.testQuoteReadiness_noAttachment_addsFailure --tests StageGateServiceTest.testQuoteReadiness_withAttachment_passes --target-org My_Org --result-format human
```

Expected: 2 tests FAIL (`첨부 룰이 추가되어 있어야 함` assertion failure).

- [ ] **Step 5.3: StageGateService.cls 의 checkQuoteReadiness 확장 + evaluateRules 룰 추가**

`checkQuoteReadiness` (line 109~139) 의 status Map 에 `hasAttachment` 추가:

```apex
private static Map<String, Boolean> checkQuoteReadiness(Id oppId) {
    Map<String, Boolean> status = new Map<String, Boolean>{
        'quoteExists'    => false,
        'hasLineItems'   => false,
        'isSent'         => false,
        'hasAttachment'  => false   // 신규
    };

    List<Quote> quotes = [
        SELECT Id, Status
        FROM Quote
        WHERE OpportunityId = :oppId
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (quotes.isEmpty()) return status;

    Quote q = quotes[0];
    status.put('quoteExists', true);

    List<QuoteLineItem> items = [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id LIMIT 1];
    status.put('hasLineItems', !items.isEmpty());

    status.put('isSent', q.Status == 'Sent' || q.Status == '발송');

    Integer attCount = [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :q.Id
    ];
    status.put('hasAttachment', attCount > 0);

    return status;
}
```

`evaluateRules` 의 `STAGE_QUOTE_BUILDING → STAGE_QUOTE_SENT` 분기 (line 83~95) 에 3번째 GateRule 추가:

```apex
else if (fromStage == STAGE_QUOTE_BUILDING && toStage == STAGE_QUOTE_SENT) {
    Map<String, Boolean> quoteStatus = checkQuoteReadiness(oppId);
    rules.add(new GateRule(
        '견적 존재',
        quoteStatus.get('quoteExists'),
        'Quote Builder에서 견적 생성 필요'
    ));
    rules.add(new GateRule(
        '견적 라인',
        quoteStatus.get('hasLineItems'),
        '견적 라인 1개 이상 추가 필요'
    ));
    rules.add(new GateRule(
        '견적 첨부 파일',
        quoteStatus.get('hasAttachment'),
        '견적서 PDF 생성 또는 직접 업로드 (Files 영역에 1개 이상)'
    ));
}
```

- [ ] **Step 5.4: 신규 테스트 통과 확인**

```bash
sf apex run test --tests StageGateServiceTest --target-org My_Org --code-coverage --result-format human
```

Expected: 모든 `StageGateServiceTest` PASS (기존 + 신규 2 = 14+).

- [ ] **Step 5.5: 기존 회귀 — 다른 곳에서 견적 작성→발송 전환하는 테스트 있으면 첨부 추가**

```bash
sf apex run test --tests "RunLocalTests" --target-org My_Org --result-format human --code-coverage 2>&1 | grep -E "Fail|FAIL"
```

만약 `QuoteEmailService_Test` 같은 곳에서 견적 작성→발송 전환을 통과 가정한 테스트가 새 첨부 룰로 깨지면 — 해당 테스트 setup 에 ContentVersion+ContentDocumentLink 인서트 추가.

(주의: `evaluateFailures` 는 trigger 에서만 호출되고 일반적으로 stageGate 전환을 외부에서 직접 시도하는 테스트는 적음. 회귀 발생 가능성 낮지만 확인.)

- [ ] **Step 5.6: 배포 + 전체 회귀**

```bash
sf project deploy start --source-dir force-app/main/default/classes/opp --target-org My_Org --ignore-warnings --test-level RunLocalTests
```

Expected: `Succeeded`, all tests PASS (319+ → 321+).

UI 검증:
1. 임의 Opp StageName='견적 작성' + Quote+Line 1+ + 첨부 0건 → stageGateChecklist 에 ❌ "견적 첨부 파일" 표시
2. [PDF 생성] 클릭 → Quote 에 ContentDocumentLink 1건 생성 → stageGateChecklist 새로고침 → ✅ "견적 첨부 파일"

---

## Task 6: 챗봇 스타일 입력바

**Files:**
- Modify: `force-app/main/default/lwc/agentforceInputBar/agentforceInputBar.html`
- Modify: `force-app/main/default/lwc/agentforceInputBar/agentforceInputBar.js`
- Modify: `force-app/main/default/lwc/agentforceInputBar/agentforceInputBar.css`

먼저 기존 LWC 구조 확인:

- [ ] **Step 6.1: 기존 agentforceInputBar 3 파일 읽기**

```bash
ls force-app/main/default/lwc/agentforceInputBar/
```

각 파일 내용 파악 (HTML 구조, JS state, CSS 클래스).

- [ ] **Step 6.2: agentforceInputBar.js — 메시지 누적 상태 + ID 파서 (Task 3 통합) + AI_Loading_Message (Task 4 통합)**

기존 `handleSend` (또는 동등 이름) 함수 + state 를 다음 구조로 변경:

```js
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import ask from '@salesforce/apex/AgentforceInputBarService.ask';
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';

export default class AgentforceInputBar extends NavigationMixin(LightningElement) {
    @api recordId;
    @track messages = [];   // { id, role: 'user'|'ai', segments: [{text, recordId}], action, urgency }
    @track inputText = '';
    @track isLoading = false;
    labels = { aiLoading: AI_LOADING };

    static MSG_CAP = 50;
    nextMsgId = 1;

    handleInputChange(e) { this.inputText = e.target.value; }

    handleKeyup(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSend();
        }
    }

    async handleSend() {
        const text = (this.inputText || '').trim();
        if (!text || this.isLoading) return;

        // user 메시지 추가
        this.pushMessage({
            role: 'user',
            segments: [{ text, recordId: null }]
        });
        this.inputText = '';
        this.isLoading = true;

        try {
            const resp = await ask({ utterance: text, contextRecordId: this.recordId });
            const segs = this.parseInlineIds(resp.message || '');
            this.pushMessage({
                role: 'ai',
                segments: segs,
                action: resp.action,
                urgency: resp.urgency,
                isLlmFallback: resp.action === 'llm_fallback'
            });
        } catch (e) {
            this.pushMessage({
                role: 'ai',
                segments: [{ text: '오류: ' + (e?.body?.message || e?.message || 'unknown'), recordId: null }],
                action: 'error',
                isError: true
            });
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    pushMessage(m) {
        m.id = this.nextMsgId++;
        m.cssClass = this.cssFor(m);
        m.avatar = m.role === 'user' ? '🙋' : '🤖';
        const arr = [...this.messages, m];
        // cap
        this.messages = arr.length > AgentforceInputBar.MSG_CAP
            ? arr.slice(arr.length - AgentforceInputBar.MSG_CAP)
            : arr;
        this.scrollToBottom();
    }

    cssFor(m) {
        if (m.role === 'user') return 'msg msg-user';
        if (m.isError) return 'msg msg-ai msg-error';
        if (m.isLlmFallback) return 'msg msg-ai msg-llm';
        return 'msg msg-ai msg-action';
    }

    scrollToBottom() {
        setTimeout(() => {
            const log = this.template.querySelector('.chatbot__log');
            if (log) log.scrollTop = log.scrollHeight;
        }, 0);
    }

    parseInlineIds(message) {
        if (!message) return [{ text: '', recordId: null }];
        const re = /(\S+?)\{\{id:([a-zA-Z0-9]{15,18})\}\}/g;
        const segments = [];
        let lastIdx = 0, m;
        while ((m = re.exec(message)) !== null) {
            if (m.index > lastIdx) {
                segments.push({ text: message.slice(lastIdx, m.index), recordId: null });
            }
            segments.push({ text: m[1], recordId: m[2] });
            lastIdx = re.lastIndex;
        }
        if (lastIdx < message.length) {
            segments.push({ text: message.slice(lastIdx), recordId: null });
        }
        return segments;
    }

    handleNav(e) {
        e.preventDefault();
        const id = e.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' }
        });
    }
}
```

- [ ] **Step 6.3: agentforceInputBar.html — 챗봇 레이아웃**

기존 전체 template 교체:

```html
<template>
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
                            <template for:each={m.segments} for:item="s">
                                <template lwc:if={s.recordId}>
                                    <a key={s.text} href="javascript:void(0)" data-id={s.recordId} onclick={handleNav}>{s.text}</a>
                                </template>
                                <template lwc:else>
                                    <span key={s.text}>{s.text}</span>
                                </template>
                            </template>
                        </div>
                    </div>
                </template>

                <template lwc:if={isLoading}>
                    <div class="msg msg-ai msg-typing">
                        <div class="avatar">🤖</div>
                        <div class="bubble">
                            <span class="dot"></span><span class="dot"></span><span class="dot"></span>
                            <span class="slds-text-color_weak slds-m-left_x-small">{labels.aiLoading}</span>
                        </div>
                    </div>
                </template>
            </div>

            <div class="chatbot__input">
                <lightning-input
                    type="text"
                    variant="label-hidden"
                    placeholder="예: 오늘 우선순위, 현대모비스 미수금, 납기 위험 주문…"
                    value={inputText}
                    onchange={handleInputChange}
                    onkeyup={handleKeyup}
                    disabled={isLoading}>
                </lightning-input>
                <lightning-button-icon
                    icon-name="utility:send"
                    variant="brand"
                    alternative-text="보내기"
                    title="보내기"
                    onclick={handleSend}
                    disabled={isLoading}>
                </lightning-button-icon>
            </div>
        </div>
    </lightning-card>
</template>
```

(주의: `for:each` 안의 `for:each` 는 key 필수 — segments 의 key 는 segment 텍스트로. 중복 가능성 있으니 인덱스 key 가 더 안전한데 LWC `for:item="s" for:index="i"` + `key={i}` 사용. 이 패턴으로 교체 — `key={s.text}` 부분을 인덱스 key 로:)

```html
<template for:each={m.segments} for:item="s" for:index="i">
    <template lwc:if={s.recordId}>
        <a key={i} href="javascript:void(0)" data-id={s.recordId} onclick={handleNav}>{s.text}</a>
    </template>
    <template lwc:else>
        <span key={i}>{s.text}</span>
    </template>
</template>
```

- [ ] **Step 6.4: agentforceInputBar.css — 챗봇 비주얼**

```css
.chatbot {
    display: flex;
    flex-direction: column;
    height: 480px;
}
.chatbot__header {
    display: flex;
    align-items: center;
    padding: 0.5rem 1rem;
    border-bottom: 1px solid rgb(229, 229, 229);
    background: linear-gradient(90deg, #635bff 0%, #8a82ff 100%);
    color: white;
    border-radius: 0.25rem 0.25rem 0 0;
}
.chatbot__header .bot-icon { font-size: 1.4rem; margin-right: 0.5rem; }
.chatbot__header .bot-title { font-weight: 600; }

.chatbot__log {
    flex: 1 1 auto;
    overflow-y: auto;
    padding: 0.75rem 1rem;
    background: #f6f6fb;
}
.msg {
    display: flex;
    margin-bottom: 0.6rem;
    align-items: flex-start;
}
.msg .avatar {
    flex: 0 0 auto;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: #eee;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    margin: 0 0.4rem;
}
.msg .bubble {
    max-width: 75%;
    padding: 0.5rem 0.75rem;
    border-radius: 0.75rem;
    background: white;
    box-shadow: 0 1px 2px rgba(0,0,0,0.04);
    line-height: 1.4;
    word-break: break-word;
}
.msg-user {
    flex-direction: row-reverse;
}
.msg-user .bubble {
    background: #d6d6d6;
    color: #222;
    border-bottom-right-radius: 0.15rem;
}
.msg-ai .bubble {
    background: #e7eaff;
    border-bottom-left-radius: 0.15rem;
}
.msg-ai.msg-llm .bubble {
    background: #efe2ff;
    border-left: 3px solid #8e5cd9;
}
.msg-ai.msg-error .bubble {
    background: #ffe6e6;
    border-left: 3px solid #c00;
}
.msg-ai .bubble a {
    color: #3a3aff;
    text-decoration: underline;
    cursor: pointer;
}

.msg-typing .bubble {
    display: flex;
    align-items: center;
    background: #e7eaff;
}
.msg-typing .dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    margin: 0 2px;
    border-radius: 50%;
    background: #635bff;
    animation: typing-bounce 1.2s infinite;
}
.msg-typing .dot:nth-child(2) { animation-delay: 0.2s; }
.msg-typing .dot:nth-child(3) { animation-delay: 0.4s; }

@keyframes typing-bounce {
    0%, 80%, 100% { transform: translateY(0); opacity: 0.3; }
    40%           { transform: translateY(-4px); opacity: 1; }
}

.chatbot__input {
    display: flex;
    align-items: center;
    padding: 0.5rem 0.75rem;
    border-top: 1px solid rgb(229, 229, 229);
    background: white;
    gap: 0.4rem;
}
.chatbot__input lightning-input { flex: 1 1 auto; }
```

- [ ] **Step 6.5: 배포**

```bash
sf project deploy start --source-dir force-app/main/default/lwc/agentforceInputBar --target-org My_Org --ignore-warnings
```

Expected: `Succeeded`, 3 components Changed.

- [ ] **Step 6.6: UI 시연 검증 (3건)**

Home 페이지에서:
1. "오늘 우선순위" 입력 → user 메시지 (오른쪽 회색) + 타이핑 점 점멸 + AI 응답 (왼쪽 파랑) 누적 표시.
2. "대성기공(주) 물건 나갔나요?" → AI 응답에 회사명이 underline 링크 → 클릭 시 Account 페이지로 이동 (Task 3 통합 확인).
3. "안녕하세요" → 보라색 LLM fallback 버블.
4. 5건 누적 후 자동 스크롤, 입력창 활성/비활성 동작 확인.

---

## Self-Review (post-write 점검)

**Spec coverage check** (Spec §1 6 항목 ↔ Task 매핑):

| Spec | Task |
|---|---|
| #1 협상→수주 안내 | Task 1 ✅ |
| #2 납기일 표시 | Task 2 ✅ |
| #3 AI 응답 인라인 ID | Task 3 (Prompt) + Task 6 (LWC 파서) ✅ |
| #4 공통 로딩 메시지 | Task 4 ✅ |
| #5 견적 첨부 게이트 | Task 5 ✅ |
| #6 챗봇 스타일 | Task 6 ✅ |
| D33 의사결정 | Plan goal/architecture 에 명시 ✅ |

**Type consistency check**:
- `GateResult.rules` = `List<GateRule>` — 모든 task 일관
- `GateRule(label, satisfied, hintText)` 3-arg — Task 5 신규 룰도 동일 시그니처 사용
- `AeCockpitService.RiskyOrderRow` DTO — Task 2 에서 `endDate: Date`, `dueLabel: String` 추가, LWC 도 같은 이름
- `AgentforceInputBarService.AgentResponse.message` — Task 3/6 의 파서가 이 필드 처리
- LWC `messages[]` 의 segment 모양 — Task 6 의 parseInlineIds 가 `{text, recordId}` 반환, HTML 도 이 모양 소비

**Placeholder scan**: 모든 step 에 실제 코드/명령. 회귀(Step 5.5) 부분만 "있으면 추가" 표현 — 정상 (조건 분기).

---

## Execution checklist (sanity)

작업 순서 권장 (의존성 최소화):
1. Task 1 (LWC-only, 위험 0) — 가장 빠른 win
2. Task 5 (Apex 견적 게이트, Test 추가, 회귀 가능성 있음 — 일찍 잡아야 함)
3. Task 2 (DTO + LWC 확장, 시드 백필)
4. Task 4 (CustomLabel + 6 LWC — Task 6 의 agentforceInputBar 는 제외하고 6개만)
5. Task 3 (AgentSynthesize Prompt — 2단계 활성화)
6. Task 6 (agentforceInputBar 전면 개편 — Task 3 의 마커 규칙 + Task 4 의 AI_Loading_Message 두 가지 통합)

각 Task 종료 시 RunLocalTests 1회 회귀 권장. 최종 예상 PASS: 319 + Task 2 의 1 + Task 5 의 2 = **322/322**.
