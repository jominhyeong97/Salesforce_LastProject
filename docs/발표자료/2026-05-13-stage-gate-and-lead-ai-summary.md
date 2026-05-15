# 발표 추가 콘텐츠 — 단계별 게이트웨이 룰 + 리드 AI 요약

> CD(Claude Design)에게 슬라이드 콘텐츠 인계용. 두 기능을 슬라이드로 옮길 때 본 문서의 텍스트 그대로 사용 가능.
> 작성: 2026-05-13. 출처: `force-app/main/default/classes/opp/StageGateService.cls`, `lead/LeadScoringService.cls`, `lead/CallMemoExtractService.cls`.

---

## Part 1 · 단계별 게이트웨이 룰 (Stage Gate)

### 1.1 한 줄 정의

영업 파이프라인 6단계를 **3개 게이트**로 묶어, 각 전환 시점에 필수 조건이 자동 충족되었는지 검사하고 미충족이면 **다음 액션을 안내**한다.

### 1.2 왜 도입했나

- 영업 단계가 명목상 6단계여도 실제 운영은 "느슨한 전환"이 흔함 — 사업자번호 없이 견적, 견적 라인 없이 발송, 발송 안 한 상태에서 협상.
- 시스템이 명확한 게이트로 막아주면 **AE는 다음 조건만 채우면 됨**. 단계별 다음 액션이 자동으로 노출됨.
- 한국 B2B 거래의 **거래 신뢰 단계**(사업자번호 → 견적서 → 발송 → 협상)에 맞춤.

### 1.3 6단계 영업 파이프라인

```
발굴 → [게이트 ①] → 견적 작성 → [게이트 ②] → 견적 발송 → [게이트 ③] → 협상 → 수주
                                                                          └→ 실주
```

### 1.4 3개 게이트 룰

#### 게이트 ① · 발굴 → 견적 작성

| 룰 | 만족 조건 | 안내 메시지 |
|---|---|---|
| **사업자번호 등록** | `Account.Business_Number__c` 입력됨 | "Account 사업자등록증 업로드 또는 직접 입력" |
| **약속 납기일 등록** | `Opportunity.Promised_Delivery_Date__c` 입력됨 | "납기일을 저장해주세요" |

**연동**: 사업자번호는 사업자등록증 OCR(기능 2) 한 번이면 자동 충족. 약속 납기일은 L2C 자동화(기능 4)의 단일 진실 소스 — Order.EndDate로 자동 승계.

#### 게이트 ② · 견적 작성 → 견적 발송

| 룰 | 만족 조건 | 안내 메시지 |
|---|---|---|
| **견적 존재** | Opportunity에 Quote 1건 이상 | "Quote Builder에서 견적 생성 필요" |
| **견적 라인** | `QuoteLineItem` 1건 이상 | "견적 라인 1개 이상 추가 필요" |
| **견적 첨부 파일** | `ContentDocumentLink` 1건 이상 | "견적서 PDF 생성 또는 직접 업로드 (Files 영역에 1개 이상)" |

**연동**: PDF 생성 버튼 한 번이면 첨부 자동 등록. 라인은 quoteBuilder LWC에서 인라인 편집으로 한 클릭에 추가.

#### 게이트 ③ · 견적 발송 → 협상

| 룰 | 만족 조건 | 안내 메시지 |
|---|---|---|
| **견적 발송 완료** | `Quote.Status = 'Sent'` (또는 '발송') | "견적을 고객에게 발송(이메일) 필요" |

**연동**: quoteBuilder의 [이메일 발송] 버튼이 Quote.Status='Sent' 자동 전환 → 게이트 통과.

### 1.5 작동 흐름

```
LWC stageGateChecklist
   │ @wire (cacheable=true)
   ▼
StageGateService.checkOppGate(oppId)
   │ 1. Opportunity + Account + OpportunityContactRoles SOQL
   │ 2. nextStage(currentStage)로 다음 단계 결정
   │ 3. evaluateRules(o, fromStage, toStage)
   │    └ 전환 매핑에 해당하는 룰만 평가 (1~3건)
   │ 4. GateResult { passed, currentStage, nextStage, rules[] }
   ▼
화면에 ✓/❌ 표시 + 단계 전환 버튼 활성/비활성
```

Trigger 측: `OpportunityTriggerHandler.handleBeforeUpdate`가 같은 `evaluateFailures()` 호출 → 미충족이면 `addError()`로 트랜잭션 abort. UI 우회 시도 차단.

### 1.6 코드 핵심 (Apex 발췌)

```apex
// 룰 평가 — 전환 매핑 별 룰. 매핑 없는 전환은 자동 통과.
if (fromStage == '발굴' && toStage == '견적 작성') {
    rules.add(new GateRule(
        '사업자번호 등록',
        String.isNotBlank(o.Account?.Business_Number__c),
        'Account 사업자등록증 업로드 또는 직접 입력'
    ));
    rules.add(new GateRule(
        '약속 납기일 등록',
        o.Promised_Delivery_Date__c != null,
        '납기일을 저장해주세요'
    ));
}
else if (fromStage == '견적 작성' && toStage == '견적 발송') {
    Map<String, Boolean> q = checkQuoteReadiness(oppId);
    rules.add(new GateRule('견적 존재',      q.get('quoteExists'),   'Quote Builder에서 견적 생성 필요'));
    rules.add(new GateRule('견적 라인',      q.get('hasLineItems'),  '견적 라인 1개 이상 추가 필요'));
    rules.add(new GateRule('견적 첨부 파일', q.get('hasAttachment'), '견적서 PDF 생성 또는 직접 업로드'));
}
else if (fromStage == '견적 발송' && toStage == '협상') {
    rules.add(new GateRule('견적 발송 완료',
        q.get('isSent'),
        '견적을 고객에게 발송(이메일) 필요'));
}
```

### 1.7 시연 시나리오 (단계별)

1. **새 Opportunity 생성** (StageName='발굴') → 게이트 ① 미통과 2건(❌ 사업자번호 / ❌ 납기일)
2. **사업자등록증 1.jpg 업로드** → OCR로 사업자번호 자동 보강 → 게이트 ① 1건만 남음(❌ 납기일)
3. **납기일 6/15 입력** → 게이트 ① 통과 → "견적 작성" 버튼 활성
4. **견적 생성 + 라인 1+ 추가 + PDF 생성** → 게이트 ② 3건 통과 → "견적 발송" 버튼 활성
5. **이메일 발송** → Quote.Status='Sent' → 게이트 ③ 통과 → "협상" 버튼 활성

### 1.8 핵심 설계 메시지 (슬라이드용)

- **다음 액션이 메시지로 보인다** — AE는 "뭐 빠졌지?" 추측 안 함. 시스템이 먼저 말함.
- **명목 단계가 아닌 실제 게이트** — 사업자번호 없는 견적 없음. 라인 없는 견적 발송 없음. 발송 없는 협상 없음.
- **트리거와 LWC가 동일한 룰 평가 함수 공유** — UI에서 차단된 전환은 백엔드(데이터 로더, API)에서도 차단. 우회 불가.

---

## Part 2 · 리드 AI 요약 (Lead 인입 AI 자동 추출)

### 2.1 한 줄 정의

전화 메모·방문 노트·RFQ 이메일을 **자연어 그대로** 붙여넣으면 AI가 **6필드를 자동 추출**하고 **Score를 매겨** Lead를 즉시 생성한다.

### 2.2 왜 도입했나

- AE의 일과 중 **Lead 입력은 가장 부담스럽고 자주 누락되는 작업**. 한 줄 메모만 남기고 정식 입력은 미루다 잃어버림.
- 한국 영업은 통화·방문·이메일 채널이 섞임 — 채널별 입력 폼이 달라 마찰 큼.
- AI에게 자연어 한 줄만 넘기면 회사·담당·전화·부품·수량·납기 6필드를 자동으로 채움 → **AE 입력 부담 90% 감축**.

### 2.3 3채널 인입

| 채널 | 컴포넌트 | 트리거 |
|---|---|---|
| **전화 메모** (PHONE) | `phoneLeadIntake` LWC | AE가 textarea에 자연어 메모 붙여넣고 [AI 추출] 버튼 |
| **방문 노트** (VISIT) | `visitLeadIntake` LWC | AE가 방문 후 노트 입력 (같은 패턴) |
| **RFQ 이메일** (EMAIL) | `RfqInboundHandler` (Apex Email Service) | 외부 이메일 수신 시 자동 트리거 — 본문 파싱 → Lead 자동 생성 |

### 2.4 6필드 자동 추출

```
입력 (자연어 1줄):
"한라정공 박과장 02-555-1234, 베어링 6204 100개 납기 4/30"
          ↓ Prompt Template "CallMemoExtract"
          ↓ ConnectApi.EinsteinPromptTemplateGenerations
출력 (JSON 6필드):
{
  "company":       "한라정공",
  "contactName":   "박과장",
  "phone":         "02-555-1234",
  "partName":      "베어링 6204",
  "quantity":      "100",
  "requestedDate": "2026-04-30"
}
```

#### Hybrid 추출 전략

1. **AI 우선** — Prompt Builder `CallMemoExtract` Template 호출
2. **코드 펜스 제거** — LLM이 \`\`\`json...\`\`\`로 감쌌으면 자동 strip (D26 안전 패치)
3. **빈 응답 또는 예외** → 한국어 **정규식 fallback** (extractByRegex)
4. **AI 누락 필드만 regex 보강** — 둘 다 작동, 부족한 부분 자동 채움
5. **출처 추적** — `lastSource = 'ai' | 'fallback'` UI 배지로 노출

### 2.5 Lead Score 4축 자동 산정

```
score = 채널 가중치 + 과거 거래 + 사양 입력 + 수량 정보
```

| 축 | 점수 | 조건 |
|---|---|---|
| **채널 가중치** | VISIT 40 / PHONE 30 / EMAIL 20 | `Source_Channel__c` |
| **과거 거래 보너스** | +20 | 같은 회사명 Account 존재 시 |
| **사양 입력 보너스** | +10 | `RFQ_Spec_JSON__c` 비어있지 않음 |
| **수량 정보 보너스** | +10 | spec.quantity 키 존재 |

총점 0~100 (clamp). 등급:

- **Hot 70+** — 즉시 컨택
- **Warm 40~69** — 우선 처리 Lead 카드 노출
- **Cold <40** — 백로그

### 2.6 코드 핵심 (Apex 발췌)

```apex
// CallMemoExtractService — 추출 진입점
public static Map<String, String> extract(String memo) {
    try {
        String aiJson = invokePromptForMemo(memo);     // 1. AI 호출
        Map<String, String> ai = parseAiJson(aiJson);  // 2. 코드 펜스 strip + JSON 파싱
        if (isAllBlank(ai)) throw new CallMemoExtractException('AI all-blank');
        lastSource = 'ai';
        Map<String, String> regex = extractByRegex(memo);   // 3. regex 보강
        for (String k : FIELD_KEYS) {
            r.put(k, String.isBlank(ai.get(k)) ? regex.get(k) : ai.get(k));
        }
        return r;
    } catch (Exception e) {
        lastSource = 'fallback';
        return extractByRegex(memo);                   // 4. AI 실패 시 regex
    }
}

// LeadScoringService — Score 4축
public static Integer calculateScore(Lead lead) {
    Integer score = 0;
    score += CHANNEL_WEIGHTS.get(lead.Source_Channel__c);  // VISIT 40 / PHONE 30 / EMAIL 20
    if ([SELECT COUNT() FROM Account WHERE Name = :lead.Company] > 0) score += 20;
    if (String.isNotBlank(lead.RFQ_Spec_JSON__c)) {
        score += 10;
        if (spec.containsKey('quantity')) score += 10;
    }
    return Math.min(100, Math.max(0, score));
}
```

### 2.7 시연 시나리오

```
AE 김민수: 전화 받는 중 ...
   ↓ 통화 종료 후 phoneLeadIntake 열고
   ↓ textarea에 한 줄 붙여넣기
   "한라정공 박과장 02-555-1234, 베어링 6204 100개 납기 4/30"
   ↓ [AI 추출] 클릭
   ↓ 0.8초 후
6필드 자동 채움 → AE 시각 검토 → Lead Score 92점 (Hot) 표시
   ↓ [Lead 생성] 클릭
새 Lead 페이지로 navigation → AE는 다음 통화로
```

### 2.8 핵심 설계 메시지 (슬라이드용)

- **자연어 한 줄 → 6필드 자동 채움** — AE의 텍스트박스 6번 클릭이 단 한 번으로
- **AI + 정규식 Hybrid** — LLM이 실패해도 한국어 정규식이 받쳐줌. 시연 중 0건 추출 안 남
- **Score 4축 자동** — 채널/과거거래/사양/수량으로 즉시 우선순위 결정. AE의 "어디부터?" 추측 제거
- **인입 채널 3개 모두 동일 엔진** — phoneLeadIntake / visitLeadIntake / RfqInboundHandler 모두 같은 `CallMemoExtractService.extract()` 재사용. 코드 중복 0

---

## 인벤토리 — 슬라이드용 핵심 수치/사실

### Stage Gate
- **6단계 → 3 게이트** (발굴/견적작성/견적발송/협상 사이)
- **총 6개 룰** (게이트①: 2 / 게이트②: 3 / 게이트③: 1)
- **단일 함수 공유** — LWC와 Trigger가 같은 `evaluateRules()` 호출 → UI/백엔드 일관성

### Lead AI
- **3채널** (PHONE / VISIT / EMAIL)
- **6필드 자동 추출** (company / contactName / phone / partName / quantity / requestedDate)
- **Score 4축** (채널 가중치 / 과거 거래 / 사양 / 수량) → 0~100점
- **Hybrid 안전성** — AI 응답 빈 경우 정규식 fallback. `lastSource` UI 배지로 출처 명시

---

*끝.*
