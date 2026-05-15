# Sales Cockpit — 한도정밀 L2C

> Agentforce + Prompt Builder + LWC + Apex 로 구성한 Lead-to-Cash 영업 워크스페이스 데모

## 개요

가상의 부품·장비 제조사 **한도정밀**을 페르소나로, Lead 인입부터 Quote, Order, ERP 납기 게이트, 미수금 회수까지 영업 사원의 하루 동선을 한 화면으로 묶은 Salesforce 앱입니다. Agentforce 자연어 입력바, Prompt Builder 멀티모달 OCR(사업자등록증), Stage Gate, ERP 동기화 Mock, 입금 등록·장기미수 회수 워크플로우가 포함됩니다.

- 발표일: 2026-05-14
- 작업 기간: 2026-05-07 ~ 2026-05-13 (약 7일)
- 타깃 Org: Agentforce DE Org, API v66.0
- 외부 callout: 0건 (ERP/OCR 모두 내부 Mock 또는 Prompt Builder)

## 기술 스택

| 레이어 | 사용 기술 |
| --- | --- |
| UI | Lightning Web Components (LWC), Lightning App, Custom Tabs |
| 자동화 | Apex Trigger Handler 패턴, Flow, StageGateService |
| AI | Agentforce (GenAiPlanner / GenAiPlugin / GenAiFunction × 6), Prompt Builder Templates × 7 (멀티모달 OCR 포함) |
| 데이터 | Custom Object `Payment__c` + 표준 객체 한국형 커스텀 필드 31종, StandardValueSet 한국어 |
| 보안 | Permission Set `Sales_Cockpit_User`, FLS·CRUD 게이트 |
| 테스트 | Apex 테스트 (Org-wide ≥ 85% 커버리지) |

## 메타데이터 규모

| 타입 | 개수 |
| --- | --- |
| Apex Classes | 161 |
| Apex Triggers | 12 |
| LWC | 72 파일 (컴포넌트 다수) |
| Custom Objects / Fields | 37 객체 폴더 |
| Layouts | 169 |
| GenAi Prompt Templates | 11 |
| GenAi Functions | 6 |
| Permission Sets | 3 |

## 디렉토리

```
force-app/main/default/   # Salesforce 메타데이터 전체
  classes/                # 도메인별 폴더 (account, lead, opp, quote, order, erp, ar, agentforce, cockpit)
  triggers/               # 도메인별 폴더
  lwc/                    # Lightning Web Components
  genAiFunctions/         # Agentforce Action 6종
  genAiPromptTemplates/   # Prompt Builder 템플릿 7종 + 멀티모달 OCR
  objects/                # Payment__c + 표준객체 커스텀필드
config/                   # scratch org 정의
scripts/apex/             # 시드, cleanup, 검증 스크립트
scripts/soql/             # 진단 쿼리
specs/                    # SalesCockpitAssistant.yaml 등
docs/                     # 기획서, 설계서, 발표자료 (Markdown)
ref/                      # 참고 자료
HANDOFF.md                # 일자별 인계 문서 (v15)
WORKLOG.md                # 작업 로그 (분 단위)
```

## 핵심 시연 동선

1. **Lead 인입** — 전화 메모 / 방문 노트 / RFQ 이메일 → Prompt Builder + 정규식 hybrid 로 6필드 자동 추출, Lead Score 4축 산정
2. **사업자등록증 OCR** — Prompt Builder 멀티모달로 이미지 → 사업자번호·대표자·주소·업종 파싱, Account 자동 생성
3. **Stage Gate** — Opportunity 단계 전환 시 사업자번호 검증 게이트 (Apex Trigger)
4. **Quote → Order** — 한국어 Picklist (`발굴 / 견적 작성 / 견적 발송 / 협상 / 수주 / 실주`)
5. **ERP 동기화 Mock** — `orderRiskCard` 즉석 동기화 버튼, PoNumber 끝자리 + Production_Status 로 위험·정시·대형지연 결정적 분기
6. **미수금 회수** — `paymentRegister` 입금 등록, 장기미수 Top N + 분할입금 트래킹
7. **Agentforce 입력바** — 자연어 질의 → ReAct LLM 라우팅 → 6 Action (오늘 우선 리스트, 입금 조회, 미수금 Top, 고객사 잔액 등)

## 빌드 / 배포

```powershell
# 의존성 설치
npm install

# Org 인증 (예시)
sf org login web --alias My_Org --instance-url https://login.salesforce.com

# 메타데이터 배포
sf project deploy start --target-org My_Org

# Permission Set 할당
sf org assign permset --name Sales_Cockpit_User --target-org My_Org

# 시드 데이터
sf apex run --file scripts/apex/seedData.apex --target-org My_Org

# 테스트
npm test                                          # LWC Jest
sf apex run test --target-org My_Org --code-coverage --result-format human
```

## 라이선스

이 저장소는 학습·포트폴리오 목적으로 공개합니다. 페르소나(한도정밀)와 데이터는 모두 가상입니다.
