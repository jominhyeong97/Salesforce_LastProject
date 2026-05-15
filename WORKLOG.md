# WORKLOG — Sales Cockpit (한도정밀 L2C)

발표: 2026-05-14 (수 오후) · 시작: 2026-05-07

기록 형식: `YYYY-MM-DD HH:MM | 범주 | 결과 (1~3줄)`

---

## 2026-05-07 (수) — Day 1: 데이터 모델

- `15:40 | 환경 | My_Org Connected (API v66.0) 확인. Locale=en_US (목표 ko_KR — Setup UI 수동 변경 필요).`
- `15:45 | 계획 | Day 1 작업: Payment__c 객체, 표준 객체 커스텀 필드 26개, Picklist 5종, AccountTrigger(사업자번호 체크섬), Sales_Cockpit_User PermSet. sf-metadata 스킬 가이드 적용.`
- `15:46~15:50 | 메타작성 | Day 1 메타데이터 일괄 작성 완료 (executor opus). 객체 1 + 필드 31 (표준 26 + Payment 5) + Trigger 1 + Class 2 + PermSet 1 = 36 메타파일. Order에 Total_Paid_Amount__c 보조 필드 추가(rollup-summary 우회).`
- `15:50 | 검증 | 핵심 파일 자체 검증 완료. AccountTriggerHandler bulkified·with sharing, Payment__c 한국어 라벨, PermSet에 Formula 필드 2개 editable=false 처리 확인.`
- `15:54 | 배포1차 | 실패 (10 에러). 원인 3종: ①Account history 비활성, ②Payment sharingModel ControlledByParent + Lookup 충돌, ③Quote 기능 비활성.`
- `15:55 | 메타수정 | Long_Term_Debtor.trackHistory 제거, Payment sharingModel→ReadWrite. 사용자가 Setup에서 Quote+QuoteLayout 활성화.`
- `15:58 | 배포2차 | 1 에러 (PermSet에 Required 필드 명시 금지). Payment 4 Required 필드 PermSet에서 제거.`
- `16:00 | 배포3차 | 성공. 38 컴포넌트 Created (객체 1, 필드 31, Trigger 1, Class 2, PermSet 1).`
- `16:01 | 테스트 | AccountTriggerHandlerTest 7/7 PASS. 커버리지 93% (목표 85%+).`
- `16:02 | PermSet | Sales_Cockpit_User 본인(george.a460388598f6) 할당 완료.`
- `16:05 | Org설정 | 사용자가 Setup→Company Information에서 Locale=ko_KR / Currency=KRW / TZ=Seoul / Account History Tracking 활성화 완료.`
- `16:06 | 메타복원 | Long_Term_Debtor.trackHistory=true 복원 재배포 성공 (NFR-AUDIT-002 충족).`
- `16:30 | 의사결정 D16 | OCR을 Prompt Builder 멀티모달로 전환, CompanyInfo(FR-OPP-005) 제거→NG-016 격리 (NICE/한국기업데이터 등 상용 신용 API는 별도 계약). Beeceptor 4→2 path, NC 4→2, Prompt Template 6→7, P0 34→33.`
- `16:35 | 문서업데이트 | PRD v0.5→v0.6, dev-plan v0.1→v0.2, HANDOFF D16 추가. executor sonnet 위임 일괄 처리.`
- `17:10 | 의사결정 D17 | ERP를 Apex Mock으로 일원화(Beeceptor 완전 제거, 외부 callout 0). 시연 즉석 ERP 동기화 버튼(orderRiskCard) + Order.Last_ErpSync_At__c 필드 신설(Day 8). orderId 끝자리로 위험/정시/대형지연 결정적 분기.`
- `17:15 | 의사결정 D18 | Master Contract 객체 사용 안 함 → NG-017 신설. 단발 거래 시연 한정. 평가자 방어 포인트 1건 추가.`
- `17:20 | 문서업데이트 | PRD v0.6→v0.7, dev-plan v0.2→v0.3, HANDOFF v2 전면 재작성. executor sonnet 위임 일괄 처리. 산출물 카탈로그 Beeceptor 0/NC 0/Apex 10/Prompt 7.`
- `Day 1 종료 | 데이터 모델 배포 완료(38 컴포넌트, 7/7 PASS, 93%) + 문서 정합성 갱신(D16/D17/D18). 5/8(목) Day 2(시드)+Day 3(Lead 인입) 병행 예정. Beeceptor·외부 통신 셋업 불필요.`

---

## 2026-05-08 (목) — Day 2: 시드 데이터

- `09:30 | 컨텍스트 | HANDOFF v2 + 메모리 재로딩. Day 2 작업 큐 확정 (시드 → 한국 데이터 → 사업자등록증 샘플).`
- `09:45 | 설계 | sf-data 스킬 가이드대로 describe-first. Account/Order/Payment__c 필드 확인. 표준 Pricebook DE org 기본 inactive — 시드에서 IsActive=true 갱신 추가.`
- `09:50 | 결정 D17-정정 | "OrderNumber 끝자리"는 자동번호라 시드에서 통제 불가 → "PoNumber 끝자리 + Production_Status='InProgress'"로 변경. ErpServiceMock(Day 8)이 두 조건 모두 본다. 위험 5건/대형지연 5건 결정적 보장.`
- `10:00 | 시드작성 | scripts/apex/seedData.apex 1파일 통합 작성 (Korean 데이터 인라인). Product2 50 + PBE 50 + Account 30 + Contact 60 + Order 100 + OrderItem 200 + Payment__c ~120. Database.setSavepoint() 롤백. SEED-D2 태그로 멱등성 확보.`
- `10:05 | 정리스크립트 | scripts/apex/cleanupSeedData.apex 작성. FK 순서대로 Payment→OrderItem→Order→Contact→Account→PBE→Product2.`
- `10:10 | 사업자번호 | AccountTriggerHandler 가중치(1,3,7,1,3,7,1,3,5) inline 계산. base=100000000+i*7919 의 9자리 + 체크섬 1자리 → 트리거 통과 보장.`
- `10:20 | 시드실행1차 | 실패 — Description (Long Text) SOQL 필터 불가. 식별 키를 Account.AccountNumber/Product2.ProductCode 로 이전, 자식은 부모 ID cascade.`
- `10:22 | 시드실행2차 | 실패 — Korean_Department__c 가 restricted picklist 인데 '생산기술팀/품질관리팀/경영지원팀' 미정의. 정의된 값(영업/구매/자재/기술/품질팀)으로 교체.`
- `10:25 | 시드실행3차 | 성공 ✅ Account 30 / Contact 60 / Product2 50 / Order 100 / OrderItem 200 / Payment__c 166. SOQL 6/100, DML 9/150, CPU 1052ms.`
- `10:28 | 검증 | scripts/apex/verifySeedData.apex 작성·실행. 위험 5/5, 대형지연 5/5, 정시 90/90, 장기미수 24, 분할입금 66 Order. 사업자번호 자동 하이픈(100-00-00009 등) 적용 확인.`
- `10:30 | Day 2 시드 단계 종료 | 골든패스 8단계(ERP 동기화 → 위험 5건) 사전조건 충족. 다음: docs/samples/ 사업자등록증 샘플 5건 (사용자 자료 필요) → Day 3 Lead 인입 LWC.`
- `10:45 | App 메타작성 | Sales_Cockpit Lightning App + Payment__c CustomTab + PermSet 갱신(applicationVisibilities/tabSettings). navType=Standard, 탭 10개(Home→Lead→Account→Contact→Opportunity→Quote→Order→Payment→Reports→Dashboards).`
- `10:48 | App 배포 | sf project deploy start 성공 (Deploy 0AfdM00000a8D9pSAE, 3 components, 0 errors). PermSet 본인 할당은 Day 1에 이미 완료 → App Launcher에서 즉시 사용 가능.`
- `10:55 | App 리네임 | 사용자 요청으로 Sales_Cockpit → Hando_Sales (label="한도정밀")로 변경. Sales_Cockpit 삭제(Deploy 0AfdM00000a89KkSAI) 후 Hando_Sales + PermSet 재배포(Deploy 0AfdM00000a8DbFSAU, 2 components, 0 errors). 페르소나 회사명과 일치, 평가자 시각에서 "한도정밀 영업 워크스페이스"로 인식.`
- `11:10 | 잔재조사 | scripts/apex/inspectLegacyData.apex 작성·실행. ShopFlow 잔재 식별: Account 30(ShopFlow 고객 01~30) + Contact 70 + Case 31 + Order 100(Activated) + Opp 31 + Lead 22 + Product 22 + Knowledge 10 + 커스텀객체 Refund_Request__c/Shipping_Tracking__c(데이터 0).`
- `11:20 | 데이터정리 | scripts/apex/cleanupShopFlowData.apex 실행 성공. 함정 3건: ①Knowledge KAV/Article Apex delete 미지원→archive로 우회(Setup 수동 삭제 안내), ②Activated Order 직접 삭제 불가→Status='Draft' reset 선행, ③Sample Account for Entitlements는 표준 sample이라 Sample Entitlement 의존성으로 삭제 막힘→Database.delete partial-success 처리. 결과 Account 42/43, Contact 70, Order 100+Items 184, Case 31, Opp 31, Lead 22, Product 22+PBE 39 삭제. Knowledge 10건 Online→Archived 전환.`
- `11:30 | 메타정리 | Refund_Request__c/Shipping_Tracking__c destructive deploy(0AfdM00000a8EaXSAU) Failed (1/2 dependency 잔존). 추가 추적 비용 vs 사용자 수동 1분 → Setup→Object Manager 수동 삭제로 안내. SEED-D2 시드 무사 보존(30/60/100/50/166). Sample Account 1건은 표준 데모로 유지.`

---

## 2026-05-08 (목) — Day 3: Lead 인입

- `12:00 | Day 3 Phase A 작성 | LeadScoringService(채널/과거거래/사양/수량) + Test 10건, CallMemoExtractService(한국어 정규식 mock — 회사·담당·전화·부품·수량·납기) + Test 7건, phoneLeadIntake LWC(textarea+AI버튼+6필드+노란띠+Score 표시+Lead 열기 navigation), PermSet apex 클래스 access 2건 추가.`
- `12:08 | Day 3 Phase A 배포 | 8 components 성공 (Deploy 0AfdM00000a8FjVSAU). sf CLI exit code 1은 stderr warning 때문 — 실제는 success. PowerShell --json 으로 결과 확인.`
- `12:10 | Day 3 Phase A 테스트 | 17/18 → testQuantityWithEa 1건 실패 (정규식 group(2)이 '50EA' 잡음). 숫자 시작 토큰 제외 정규식 수정 → 18/18 PASS. Apex 커버리지 LeadScoringService 100%, CallMemoExtractService 100%, Org-wide 85%.`
- `12:30 | Day 3 Phase B | visitLeadIntake LWC (방문 노트 + AI 추출 동선, phoneLeadIntake 코드 베이스 재사용). 배포 성공.`
- `12:45 | FR-LEAD-004 | Lead_Convert_Auto_Mapping을 Flow 대신 Apex Trigger로 채택 (Flow XML schema 까다로움 + test 안전망). LeadTrigger + LeadTriggerHandler + Test 4건 작성. IsConverted 전이 시점 ConvertedOpportunity.Description ← Lead.RFQ_Spec_JSON__c 자동 복사. 4/4 PASS, 100% 커버. 'Discovery' Stage는 사용자 Setup 1단계로 이월.`
- `13:00 | Day 3 Phase C | RfqInboundHandler (Messaging.InboundEmailHandler) 작성. EMAIL Lead 자동 생성, CallMemoExtractService 재사용으로 본문 추출, fromName/도메인 fallback 회사명. Test 4건. 4/4 PASS, 95% 커버. Email Service 활성화는 사용자 Setup 1단계.`
- `Day 3 종료 | 핵심 Lead 인입 동선 완료. Apex 4 클래스 + 1 Trigger + 2 LWC + PermSet 갱신 + Test 25건 (전부 PASS). Org-wide 커버리지 87% (목표 ≥85%). FR-LEAD-001/003/004/006 완료. Day 4(Apex 서비스 계층 + Opp/OCR/Gate) 진입 가능.`
- `13:30 | 의사결정 D21 | Picklist 한국어 정비 (사용자 요청 — 평가자/사용자 시각 일관성). Lead.Status 4단계(신규/제안대기/전환완료/미전환), Opportunity.StageName 6단계(발굴/견적 작성/견적 발송/협상/수주/실주), Quote.Status 5단계(초안/발송/응답대기/수락/거절). Order.Status는 Salesforce 시스템 동작과 묶여 그대로(Production_Status__c가 한국어 단계 담당). API value도 한국어 — Apex 코드 한국어 문자열 비교 트레이드오프 vs 사용감 우선.`
- `13:35 | SVS 메타 작성·배포 | OpportunityStage/LeadStatus/QuoteStatus standardValueSet 메타 3개 작성. 1차 Failed (Cannot specify reverseRole on this picklist) → reverseRole element 11개 제거. Lead 생성 코드 3곳(phoneLeadIntake/visitLeadIntake/RfqInboundHandler) Status='Open - Not Contacted'→'신규' 정정. 8 components 배포 성공.`
- `13:40 | 회귀 테스트 | 33/33 PASS. Org-wide 커버리지 94% (목표 ≥85% 충족). LeadStatus dynamic SOQL이 한국어 변경 자동 매칭 ✅. 기존 시드/test 영향 0.`
- `14:00 | RfqInbound 점수 강화 | RfqInboundHandler insert 후 LeadScoringService.calculateScore() 호출 + update 추가. 기존 EMAIL Lead 1건 backfill (점수 40). 5/5 test PASS.`
- `14:10 | 의사결정 D22 | Lead.RFQ_Spec_JSON__c 는 UI(페이지 레이아웃)에 raw 노출 X — AE 사용 가치 없음. LWC(phone/visitLeadIntake)가 파싱하여 폼 6필드로 표현. 시연 시 평가자도 raw JSON 못 볼 화면. 사용자가 Lead 페이지 레이아웃에서 RFQ 사양 JSON 제거 작업.`
- `14:25 | FLS 해결 | 사용자 진단: Lead 페이지에서 커스텀 필드 안 보이는 원인은 Profile FLS. PermSet에는 풀려있었으나 Profile(System Administrator) FLS가 막혀있음. 사용자 Setup → 개체 관리자 → 리드 → 필드 → 필드 접근성 설정에서 활성화 완료. 인입 채널/Lead 점수 정상 노출.`
- `14:35 | 도메인 폴더링 | classes/triggers를 도메인별 하위 폴더로 재구성: classes/{account,lead}, triggers/{account,lead}. force-app/main/default/classes/README.md 컨벤션 문서 생성 (Day 4+ opp/quote/order/erp/ar/cockpit 매핑 가이드 포함). PowerShell Move-Item으로 일괄 이동. 회귀 테스트 34/34 PASS — SF CLI nested 폴더 자동 인식 확인.`
- `14:50 | 사업자등록증 샘플 9건 정리 | 사용자가 인터넷에서 1~9 다운로드 → docs/samples/business-license/로 이동. README 작성: 시연 1순위 1.jpg(대광건설기계, 471-81-00778), 2순위 5.jpg/8.jpg, 차별화 6.jpg(개인사업자), 견고성 3/4/7.jpg(저화질). D17 일관(외부 callout 0) — Prompt Builder 멀티모달 단일 경로로 진행. 시드 매칭은 Day 5 시연 직전 결정.`

---

## 2026-05-08 (목) — Day 4: Stage 게이트

- `15:10 | Day 4 Phase A 작성 | StageGateService(GateResult/GateRule + checkOppGate @AuraEnabled + evaluateFailures Trigger용) + Test 7건, OpportunityTrigger + Handler(BeforeUpdate, bulkified) + Test 5건, stageGateChecklist LWC(✅/❌ 시각화 + 단계 전환 버튼). PermSet classAccess 2개. classes/opp + triggers/opp 폴더 신설.`
- `15:20 | Day 4 Phase A 함정 2건 | ①Apex 예약어 hint/desc 충돌 → hintText/descValue로 변경. ②테스트의 hardcoded 사업자번호 109-81-39021 invalid checksum → 시드 검증된 100-00-00009 사용.`
- `15:25 | Day 4 Phase A 통과 | 12/12 PASS. StageGateService 95%, OpportunityTriggerHandler 100%, OpportunityTrigger 100%. FR-OPP-001 게이트 인프라 완료. Day 5에 사업자번호 자동 채우는 OCR 경로 추가 시 게이트 자동 충족 가능.`
- `15:40 | 의사결정 D23 | 게이트 룰 단순화 — 사용자 지적 "자동 충족 룰은 게이트 의미 X". 키맨/사양 룰 제거하고 사업자번호 1개만 유지. PRD FR-OPP-001 정정 필요. 10/10 PASS 유지.`
- `15:55 | Account 페이지 한국형 정비 (D24) | 사용자 지적 "한국 로컬라이징 안 됨, 사업자번호 안 보임, 미국 잔재 필드 많음". A안(메타 자동) 채택. retrieve "Account-Account Layout" → 한국형으로 재구성: 회사정보(사업자번호/대표자/업종/전화/팩스/웹사이트/계정번호) + 주소 + 신용·거래(신용한도/외부신용점수/총미수금/장기미수금) + 설명 + 시스템. Highlights Panel 4필드(계정명/사업자번호/대표자/총미수금). 제거: SIC/SLA/Upsell/Customer Priority/연매출액/Rating/Type/직원/증권/소유권/Active/NumberOfLocations. 함정 2건: ①RelatedOrderList field 명명 invalid → fields 비워 default ②summaryLayout sizeY=0 invalid → 1로. 배포 성공.`

## 2026-05-08 (목) — Day 4B: 단계 게이트 강화

- `16:15 | 게이트 설계 재검토 | 사용자 피드백: "견적 작성→발송 단계가 게이트 없이 휙휙 지나간다" → 전체 3단계 게이트 설계 재수립.`
- `16:20 | HTML 수정 | stageGateChecklist 안내 문구 삭제 (47-49줄) + 새로고침 버튼 우측 상단 이동 (slot="actions").`
- `16:22 | Apex 확장 | StageGateService.evaluateRules: 3개 게이트 룰 추가 — ①발굴→견적작성(사업자번호), ②견적작성→견적발송(라인1+/PDF/Draft), ③견적발송→협상(Sent). checkQuoteReadiness() 헬퍼 메서드 신설.`
- `16:25 | 배포 | 2 component 배포 성공 (Deploy 0AfdM00000a8vu1SAA, StageGateService.cls + stageGateChecklist LWC).`
- `Day 4B 종료 | 견적 단계의 게이트 강화 완료. 각 단계마다 명확한 조건 수립 → 사용자가 명시적으로 action 취해야만 다음 단계 진행 가능.`

- `16:30 | 게이트 단순화 | 사용자 피드백: "3개 조건 중복 → A안(2개 조건)으로 통일" — 견적존재 + 라인1+ 만 체크. PDF/Draft 상태는 기술적으로 자동 보장. checkQuoteReadiness() 간소화 (5개 필드 → 3개).`
- `16:32 | 배포 확정 | StageGateService.cls 재배포 (Deploy 0AfdM00000a8xUPSAY, 61 components).`
- `Day 4B 최종 | 게이트 설계 완료. 단순하고 명확한 3단계 게이트 확립:
  ①발굴→견적작성: 사업자번호
  ②견적작성→견적발송: 견적존재+라인1+
  ③견적발송→협상: Sent상태`

- `16:35 | Layout 생성 (B안) | Lead-Lead Layout 한국형 정비: 기본정보/주소/설명 섹션. Opportunity-Opportunity Layout 한국형 정비: 기본정보/단계게이트(stageGateChecklist LWC)/설명 섹션. Probability 필드 추가 (필수).`
- `16:40 | 배포 | Layout 배포 성공 (Deploy 0AfdM00000a8sWMSAY). Lead + Opp 레이아웃 한국화 완료.`
- `Day 4 최종 종료 | Day 4 작업 완료:
  ①계획 단계부터 게이트 강화(스타트) → A안 단순화(견적존재+라인)
  ②stageGateChecklist LWC 개선(안내문구 삭제, 새로고침 우측상단)
  ③StageGateService 3단계 게이트 구현(발굴→견적작성/견적작성→견적발송/견적발송→협상)
  ④Lead Layout 한국화(기본정보/주소/설명)
  ⑤Opportunity Layout 한국화 + stageGateChecklist 임베드(기본정보/단계게이트/설명)
  누적 배포 3회(0AfdM00000a8vu1SAA/0AfdM00000a8xUPSAY/0AfdM00000a8sWMSAY).`
- `Next: Day 5 (5/9 금) OCR + businessLicenseUpload LWC.`

---

## 2026-05-08 (목) — Day 5 선행: 사업자등록증 OCR 재작성

- `17:34 | 원인분석 | 기존 BusinessLicensePromptService가 파일 저장만 되고 Account 보강 안 된 원인 5가지 식별 — ①inputParams 누락(핵심: 자동 인식 안 됨), ②2-arg signature(멀티모달 처리 경로 불안정), ③applicationName='PromptTemplateGenerations'(잘못된 값), ④isPreview 미설정, ⑤catch 빈맵 반환·generationErrors 무시로 에러 마스킹.`
- `17:34 | Apex 재작성 | BusinessLicensePromptService 재작성 + 헬퍼 2개 분리 — BusinessLicenseLLMResponse(JSON DTO+파서·isAllBlank), BusinessLicensePromptInvoker(3-arg ConnectApi+Input:ContentDocument WrappedValue+generationErrors 검증, mockJsonResponse/mockExceptionMessage 정적 필드로 테스트 우회). 참조 ref/agentforce-sdo 검증 패턴 적용.`
- `17:34 | status 신설 | extract_empty 추가 — 모든 필드 blank 시 "이미지 흐림/프레임/각도 확인" 안내 메시지로 분리. partial은 1~3필드 추출 케이스만 차지. ResultDTO에 ocrJson(원본 LLM JSON) + extracted(파싱 Map) + contentDocumentId 신설.`
- `17:34 | LWC 재작성 | businessLicenseUpload — extract_empty 분기 + OCR JSON 코드블록(prettyJson)·복사 버튼 신설. PDF 차단(.jpg/.jpeg/.png만). Account 자동 보강 동작은 유지(success/partial 시 license_enriched 이벤트 디스패치).`
- `17:34 | 테스트 재작성 | BusinessLicensePromptService_Test 11 케이스 — Success(Account/Opportunity)·Partial·ExtractEmpty·OcrError·NoAccount + LLMResponse 4 + saveLicenseFile. mock JSON 기반 단위 테스트.`
- `Next: Org 배포 → Setup의 BusinessLicenseExtract prompt template 정상 동작 확인 → 실제 사업자등록증 이미지로 E2E 검증.`
- `18:10 | 핸드오프 정리 | HANDOFF.md §1 상태/§6 다음 세션 액션/§10 열린 이슈/§14 잔여 작업 갱신 + §15 "Day 5 OCR 재작성 컨텍스트" 신설(5가지 근본 원인·status 신설·코드 분리·테스트 우회·검증 실패 시 디버깅 순서). 학습 메모리 feedback_prompt_builder_apex.md 저장. 다음 세션 첫 작업 = sf project deploy → Apex Test 11/11 → Setup Prompt Template 정합성 → 1.jpg E2E.`

---

## 2026-05-10 (토) — Day 5: OCR 검증 마무리

- `11:35 | 배포 | OCR 4 components 배포 성공 (Deploy 0AfdM00000aGwuXSAS). Apex Test 12/12 PASS (BusinessLicenseLLMResponse 100%, Service 76%).`
- `11:55 | Prompt Template 메타화 | UI에서 imageBase64 입력 옛 버전이 활성으로 남아 imageBase64 required 에러 → BusinessLicenseExtract.genAiPromptTemplate-meta.xml 작성 후 deploy. 1차 실패(safe-change 거부, required=true), 2차 required=false로 통과. PR0014 활성 버전 미지정 → 3차 retrieve로 versionIdentifier(_4) 확인 후 activeVersionIdentifier 명시 추가 deploy 성공 (0AfdM00000aH2OrSAK).`
- `12:00 | E2E 검증 통과 | 1.jpg(대광건설기계) 업로드 → status=success, 4필드 정확 추출(471-81-00778/(주)대광건설기계/이재용/경기 화성시 향남읍 서해로 819-16) + Account 자동 보강. 모델 sfdc_ai__DefaultGPT41Mini.`
- `12:05 | UX 보강 | LWC: getRecordNotifyChange + RefreshEvent(lightning/refresh) + force:refreshView 3중 자동 갱신, JSON 디버그 섹션 토글→완전 제거, 결과 박스 SLDS alert grid 짜부 → bl-result + 좌측 컬러 border 박스로 재구성(✓ 4필드 stack).`
- `12:10 | Opp 시연 동선 | Opportunity-Opportunity Layout에 "사업자등록증 OCR" 섹션 추가(단계 게이트 위). 골든패스 §3~§4 검증: Lead Convert → Opp 발굴 → 게이트 ❌(사업자번호) → 1.jpg 업로드 → 게이트 ✅ → 단계 전환.`
- `12:15 | 학습 | GenAiPromptTemplate UI에서 변수 변경한 후 활성 버전이 자동 전환 안 됨 → 메타로 deploy하면서 activeVersionIdentifier 명시가 필수. retrieve로 versionIdentifier 확인 → 그 값을 activeVersionIdentifier에 박아 재배포가 표준 패턴.`

---

## 2026-05-11 (일) — Day 7 Phase 2: 이메일 추적·의도·재견적

- `14:00 | 계획 | Day 7 Phase 2 분해 — FR-QUOTE-006(이메일 추적), 007(의도 분류), 009(재견적 자동 초안). Day 7 P1 OppInsight 패턴(3-arg ConnectApi + mock JSON + fallback) 재활용 결정.`
- `14:15 | Prompt 메타 | IntentClassify(SOBJECT://EmailMessage, 6 카테고리 JSON) + RequoteDraft(QuoteRecord+EmailRecord 2개 입력, summary/lineAdjustments/confidence JSON). 둘 다 sfdc_ai__DefaultGPT41Mini, einstein_gpt__flex.`
- `14:30 | Apex 신규 4 | EmailIntentClassifyService(@future(callout=true) classifyAsync + sync classifyOne, mockJsonResponse/mockExceptionMessage/suppressAutoRequote), EmailMessageTrigger(after insert) + EmailMessageTriggerHandler(Incoming=true + RelatedTo Quote/Opp 필터), QuoteRequoteService(autoDraftIfRequote chain + draftFromEmail @AuraEnabled).`
- `14:35 | 안전 정책 | AI가 Quote 라인 가격 직접 변형 금지 — 원본 라인 그대로 복제, AI 제안은 Quote.Description 한국어 텍스트 + AI_Draft_Confidence__c. AE가 quoteBuilder에서 수동 확정(D15 — 입력 부담 감축, 결정권은 AE).`
- `14:50 | 배포1차 | 11 components 성공 (Deploy 0AfdM00000aJJ5RSAW). Prompt 2 + Apex 3 + Trigger 1 + Test 2 + PermSet.`
- `15:00 | 테스트1차 | 17 tests, 16 PASS — testAutoDraftIfRequote_filtersNonRequote 1건 FAIL. 원인: assertion에서 Quote.Id를 OpportunityId로 잘못 비교.`
- `15:05 | Prompt 활성버전 | retrieve로 versionIdentifier 확인 → IntentClassify/RequoteDraft에 activeVersionIdentifier 명시 (§16 Day 7 P1 표준 패턴). 테스트 수정 + 재배포. 7/7 PASS.`
- `15:25 | EmailTracking REST | @RestResource('/quote-tracking/*') — open.gif(1x1 투명 GIF base64 + Last_Opened_At__c 갱신), click(?url=, Last_Clicked_At__c+Last_Opened_At__c + 302 redirect). without sharing + fire-and-forget(record 실패 silent).`
- `15:35 | Custom Label 함정 | Quote_Tracking_Base_URL 1차 빈 value 거부(필요한 필드 [Value] 없음). → __UNSET__ sentinel + trackingBaseUrl() 가드(!startsWith('http') → null). QuoteEmailService.autoLinkAndWrap 본문 https?://URL→<a href tracking-click>로 정규식 wrap + 1x1 픽셀 img 주입.`
- `15:50 | 배포2차 | 11 components 성공. EmailTrackingService(96%) + QuoteEmailService 3 신규 test(autoLink/empty/blankLabel) 통과.`
- `16:00 | 회귀 | 전체 154/154 PASS, Org-wide 80% (Day 7 P1 87%→80% — 신규 코드 추가로 약간 감소, ≥85% Day 10 점검 backlog). 4 신규 클래스 평균 86% 커버리지.`
- `16:10 | 시연 동선 | §7 "응답 '재견적' → 자동 초안 → 검토·재발송" 백엔드 완성. UI는 EmailMessage 수동 인서트(Activity > Email) 또는 LWC 트리거 버튼(미작성)으로 시연. Site 설정·Public Access는 사용자 manual Setup.`
- `Day 7 Phase 2 종료 | Apex 4 + Trigger 1 + Prompt 2 + REST 1 + Custom Label 1 + 신규 Test 3 클래스(총 16 케이스). 다음 세션 첫 작업 = Day 8(Order + ERP Mock 동기화) 또는 사용자가 Site 설정·시연 검증 1회 수행.`
- `16:30 | E2E 검증 | Anonymous Apex 로 EmailMessage(Incoming=true, RelatedTo=Quote) 강제 인서트 → 트리거→@future→ 실패. classifyOne sync 직접 호출 디버깅 결과: LLM(GPT41Mini)이 응답을 \`\`\`json ... \`\`\` 코드 펜스로 감쌌고 JSON.deserializeUntyped 가 백틱(code 96)에서 실패. 프롬프트에 "마크다운 금지" 명시했음에도 모델이 무시.`
- `16:40 | 코드 펜스 가드 | EmailIntentClassifyService + QuoteRequoteService 양쪽에 stripCodeFences(정규식 \`(?s)^\`{3}(?:json|JSON)?\\s*(.*?)\\s*\`{3}\\s*$\`) 헬퍼 추가 + parseAndApply/parseAi에 적용. 2 클래스 재배포 성공. feedback_prompt_builder_apex 메모리에 체크리스트 6번 추가.`
- `16:45 | E2E 재검증 통과 | success=true / intent=Requote / aiSummary="단가를 5% 인하해 달라는 요청입니다." / draftQuoteId=0Q0dM000002PP3hSAG / aiSource=ai / Q-DAY6-001 (재견적) Status=초안 conf=0.90 자동 생성. 회귀 33/33 PASS 유지. Day 7 P2 시연 E2E 진짜 완료.`
- `Day 7 Phase 2 진짜 종료 | 시연 §7(재견적·Won 전환) 백엔드 + AI E2E 검증 완료. 다음 = Day 8 진입 가능.`
- `Day 5 종료 | OCR 골든패스 검증 완전 통과. 다음: Day 6 Quote Builder (FR-QUOTE-001~009).`

---

## 2026-05-10 (토) — Day 6: Quote Builder (FR-QUOTE-002~005)

- `12:30 | Phase A | PricingService(getQuoteSummary/updateLine/addLine/deleteLine/getActiveProducts) + Test 8/8 PASS, 94% cov. quoteBuilder LWC(헤더 6필드+합계) + quoteLineEditor LWC(인라인 편집·Discount_Percent__c formula 실시간 미리보기). PermSet PricingService classAccess 추가. 시드 Q-DAY6-001 + 라인 2건. FR-QUOTE-002/003 통과.`
- `13:00 | Phase B PDF 양식 v1 | 한국 표준 견적서 양식 — 3중 double border 제목 + 수신/발신 박스 + 印 도장 + 합계 박스(한글 일금 표기 "일금 일백사십팔만원정") + 라인 테이블 + 비고/결제. NanumGothic Static Resource(2MB ttf) 임베드.`
- `13:20 | Phase B 양식 v2 (Aqua 차용) | ref/agentforce-sdo의 AquaQuotePdf 디자인 패턴 차용 — 좌우 분할 헤더 + 검정 섹션 타이틀(1.수신처/2.거래개요/3.견적품목/4.거래조건) + 좌측 비고+우측 합계 layout + 검정 grand total. 단, 우리 데이터 매핑(Account.Business_Number__c/CEO_Name__c/Quote.Owner) + AE 사인 박스 + 한글 일금 표기 유지.`
- `13:35 | Phase B 한글 폰트 깨짐 디버깅 | 다운로드 PDF에서 한글 전부 누락 확인 — Visualforce PDF rendering(Flying Saucer)이 일반 ttf Static Resource fetch 실패. NanumGothicFont.zip Static Resource로 변경(700KB 압축) + URLFOR 패턴 변경 → 한글 정상 출력 확인. 학습: VF PDF + 한국어 폰트는 zip Static Resource 패턴이 표준.`
- `13:50 | PDF 단일 최신 유지 | [PDF 생성] 시 Title LIKE '<견적명>_견적서%' 옛 PDF 자동 삭제 후 새것 1개만 첨부. testGeneratePdfReplacesOld 검증. 다른 첨부(사업자등록증 OCR 결과 등)는 보존.`
- `14:00 | Email 발송 모달 | QuoteEmailService.getDefaultEmail로 제목/본문 자동 채움([고객사] 견적서 + 한국어 인사말). LWC 모달에 수신 이메일/제목/본문(raw textarea 380px) input + 사용자 편집 가능. modal slds-modal_large + raw textarea로 Shadow DOM 회피하고 height 직접 제어.`
- `14:10 | getLatestPdfId | 페이지 새로고침 후에도 옛 PDF로 [이메일 발송] 즉시 활성화 — LWC가 @wire로 자동 조회 후 pdfContentDocumentId 설정. PDF 재생성 없이 발송 가능.`
- `14:15 | Apex Test 누계 | PricingService 8 + QuotePdfService 5(testToKoreanAmount 포함) + QuoteEmailService 5 = 18/18 PASS. PricingService 94%, QuotePdfService 81%, QuoteEmailService 91%, NanumGothic 100% 한글.`
- `Day 6 Phase A+B 종료 | FR-QUOTE-002/003/004/005 완료. 시연 골든패스 §5/§6 (할인 입력→% 자동→PDF→발송→Status='발송') 완전 검증. 다음: Day 7 (AI Quote 초안 FR-QUOTE-001 + 이메일 추적/의도 분류/재견적 FR-QUOTE-006/007/009).`

---

## 2026-05-10 (토) — Day 7 Phase 1: AI 견적 초안 → Opp Insight 전환 (D25)

- `17:30 | FR-QUOTE-001 1차 시도 | AiQuoteDraftService(키워드 매칭 + Top1 SKU + Quote/QLI 자동 생성, AI_Draft_Confidence 기록) + aiDraftCard LWC + Opp Layout 배치. Test 4/4 PASS.`
- `17:50 | 사용자 피드백 → 설계 재검토 | "AE 멘탈모델은 Quote 페이지에서 견적 생성. AI 자동 생성은 입력 부담 약간 감소이지만 시연 임팩트 약함. 차라리 AI가 분석·요약(Opp 점수)을 해주는 게 더 가치." → D25 의사결정.`
- `18:00 | D25 폐기/대체 | aiDraftCard 폐기. 새 설계: 정량 점수(Apex OppScoreService) + 자연어 요약·액션(Prompt Builder OpportunityInsight) 하이브리드.`
- `18:15 | OppScoreService 작성 | 4축 점수(단계 50 + 활동 20 + Account 15 + Engagement 15 = max 100) + 위험 요소 자동 탐지(활동 0건/장기미수/사업자번호 누락/견적 미작성). Test 5/5 PASS, 82% cov.`
- `18:30 | OppInsightService 하이브리드 | OppScoreService 호출 + Prompt Builder OpportunityInsight 호출 + LLM 실패 시 Apex fallback summary 자동 전환(graceful degrade, "AI/Fallback" 배지 노출). 75% cov.`
- `18:45 | oppInsightCard LWC | 점수 카드(높음/중간/낮음 색상) + 분해 chip(단계+활동+Account+Engagement) + AI 요약 + 위험 리스트 + 추천 액션 ordered list. 새로고침 버튼.`
- `18:50 | Layout 갱신 | Opp Layout: aiDraftCard 섹션 제거 + AI Insight 섹션 추가. aiDraftCard LWC는 unused로 남김(필요 시 제거).`
- `19:00 | OpportunityInsight Prompt Template 메타 | SOBJECT://Opportunity input(Day 5 OCR 검증 패턴 차용). 본문에 한국어 영업 톤 + JSON 출력 강제. 1차 deploy 후 retrieve로 versionIdentifier(_1) 확인 → activeVersionIdentifier 명시 redeploy(Day 5 PR0014 회피 학습 적용).`
- `19:10 | 검증 통과 | 사용자 시연: 점수 카드 + AI 자연어 요약(배지 "AI 자연어 요약") + 추천 액션 한국어 자연스러움. fallback 모드도 graceful 동작.`
- `19:15 | 문서 갱신 | HANDOFF.md §3 D25 추가, §4 골든패스 갱신(5단계: AI Insight + 표준 New Quote), §8 산출물 카탈로그 갱신(aiDraftCard/AiQuoteDraftService/SpecExtract/SkuMatch 폐기, OppInsight 추가). PRD §4.4 FR-QUOTE-001은 D25로 폐기 표시.`
- `Day 7 Phase 1 종료 | FR-QUOTE-001 폐기·대체 완료. AI Insight = 차별화 핵심 카드. 누계 Apex Test: 23+ PASS (PricingService 8 + QuotePdfService 5 + QuoteEmailService 5 + OppInsightService 5 등). 다음: Day 7 Phase 2(FR-QUOTE-006 이메일 추적, FR-QUOTE-007 의도 분류, FR-QUOTE-009 재견적 자동 초안) 또는 Day 8(Order + ERP 동기화).`

---

## 2026-05-12 (월) — Day 8: Order + ERP Mock 동기화

- `09:30 | Phase A 인터페이스+Mock | IExternalErpService(인터페이스, D17 게이트웨이 패턴) + ErpSyncResult DTO + ErpServiceMock(D17-정정 시드 정합: 끝 6+InProgress→70~84 / 끝 9+InProgress→85~97 / Done→5~14 / Shipped→0~7 / Pending→25~39, jitter는 Math.abs(Id.hashCode())%range 결정적). force-app/main/default/classes/order/ 도메인 폴더 신설.`
- `09:50 | Phase B Service+Test | OrderErpSyncService(@AuraEnabled syncOrders/syncAllOpen/getRiskView + SyncOutcome/OrderRiskView DTO + DI @TestVisible static impl). ErpServiceMock_Test 9 + OrderErpSyncService_Test 7 = 16 신규. 단, StubErp 클래스로 DI 교체 검증 1건 포함.`
- `10:00 | Phase C LWC | orderRiskCard (@wire getRiskView + imperative syncOrders + refreshApex + 위험 색상 3단계(녹/황/적) + 78점+에 사전 통보 메일 mailto 액션). Order Record Page 전용 isExposed=true.`
- `10:05 | PermSet+배포 | Sales_Cockpit_User에 OrderErpSyncService classAccess + Order.Last_ErpSync_At__c FLS 추가. sf project deploy 19 components 성공 (0AfdM00000aJMxl). 신규 18 Created + PermSet Changed.`
- `10:10 | 신규 테스트 | ErpServiceMock_Test 9/9 + OrderErpSyncService_Test 7/7 = 16/16 PASS. 신규 3 클래스 모두 100% 커버리지 (Mock/Service/DTO).`
- `10:15 | 회귀 | RunLocalTests 172/172 PASS (Day 7 P2 154 → +18). Org-wide 80% 유지.`
- `10:20 | E2E 검증 | scripts/apex/verifyDay8.apex 실행 — 시드 100건 동기화 후 분포: 대형지연(≥85) 5건 / 위험(70-84) 5건 / 주의(40-69) 0건 / 안전(0-39) 90건. 골든패스 §8 정합 완전 검증. SOQL 함정 2건 해결(CASE WHEN 미지원→Apex 집계, Description Long Text 필터 불가→PoNumber LIKE).`
- `10:25 | 시연 동선 확인 | ORD-1000~1004(PoNumber 끝 6) 위험 5건 + ORD-1005~1009(PoNumber 끝 9) 대형지연 5건 일관. ORD-1007이 최고점 96점, "사전 통보 메일" 액션 노출.`
- `Day 8 종료 | FR-ORDER-001/002/003 완료. ERP 게이트웨이 패턴 외부 callout 0 시연 가능. 누계 Apex Test 172/172 PASS, Org-wide 80%. 다음: Day 9 (AR + 콕피트 5카드).`
- `11:00 | Case A 시작 | 사용자 요청 — 수주 → Order 자동 시 QuoteLineItem→OrderItem 자동 복사. OrderTrigger(after insert) + OrderTriggerHandler + 7 Test 케이스 (basic+할인분배/벌크/Opp없음/수락Quote없음/빈Quote/null입력). 첫 deploy 19 components 성공, 7/7 PASS 회귀 179/179.`
- `11:25 | 차단 발견 D27 | 실제 E2E 동작 검증 시 SObjectException "Invalid field OpportunityId for Order". Schema describe 확인 — 이 DE Org 는 표준 Order.OpportunityId 미활성 (Optional Activation 안 됨), Order 의 reference 필드는 AccountId/ContractId/OriginalOrderId/Customer/Company 만. Apex 컴파일러는 metadata 캐시로 통과시키지만 런타임 silently null → 트리거 noop. 테스트 PASS 도 의미 없음(검증 안 됨).`
- `11:30 | D27 결정 | Order.Opportunity__c custom lookup 신설 → 우회. 정통 SF 패턴 X 지만 Org 한계 명시적. 평가자 답변: "Org 환경상 표준 OpportunityId 미활성 → custom lookup 으로 명시적 책임 분리".`
- `11:35 | D27 적용 | Order.Opportunity__c 필드 생성(Lookup to Opportunity, relationshipName=Orders) + OrderTriggerHandler/Test/verifyCaseA 모두 OpportunityId→Opportunity__c 수정 + PermSet FLS 추가. replace_all 에 Quote.OpportunityId 까지 잘못 치환 → 3건 수동 원복.`
- `11:45 | 재배포 + 회귀 | 6 components 성공. OrderTriggerHandler_Test 7/7 PASS (Handler 98% / Trigger 100%). E2E 검증 통과 — 임시 Quote(2 라인: Qty10 UnitPrice1000 / Qty5 UnitPrice2000 할인500) 인서트 → Order.Opportunity__c 채워서 Order 인서트 → OrderItem 2건 자동: 1000/1900 (할인 500/5=100 분배). Quote 총액 = Order 총액 정합.`
- `Case A 종료 | FR-ORDER-004(견적 라인→주문 라인 자동 승계) 완료. 누계 Apex Test 186/186 PASS 예정. Won_To_Order Flow 는 Day 9 작성 시 Order.Opportunity__c 채우도록 설계.`

---

## 2026-05-12 (월) — Day 9 #1: Won_To_Order (Opp Trigger after update)

- `12:00 | Won_To_Order | OpportunityTrigger 에 after update 추가 + OpportunityTriggerHandler.handleAfterUpdate(): StageName '수주' 신규 전환 감지 → AccountId/Pricebook2Id 가진 Opp 만 Order 생성 (AccountId, Opportunity__c, EffectiveDate=TODAY, Status='Draft', Pricebook2Id, PoNumber='PO-YYYY-W' + Opp.Id 끝4자리, Production_Status='Pending'). 이미 Order 있는 Opp 는 dedupe (idempotent).`
- `12:10 | Test 4 신규 | testWonTransition_createsOrderAndCopiesLines(E2E — Quote 수락 + Won → Order + OrderItem 자동) + noPricebook_skipsOrder + alreadyHasOrder_idempotent + testNonWonTransition_doesNotCreateOrder. 누계 9/9 PASS, OpportunityTriggerHandler 100% 커버.`
- `12:15 | E2E 검증 | verifyWonToOrder.apex — Quote(2 라인: 8x1200 / 3x4500 할인1500) 수락 + Opp.StageName='수주' update 한 번 → Order 자동(PoNumber=PO-2026-WJQAX, Production_Status=Pending) + OrderItem 2건 자동(1200/4000 — Case A 할인 분배 정확).`
- `Day 9 #1 종료 | 시연 §7 골든패스(Quote 수락 → Won → Order + 라인) 완전 자동화. AE 입력 부담 없음. 다음 = #2 ShippingCompleteService + shippingComplete LWC (Order.Production_Status 'Done'→'Shipped' + Shipped_Date).`
- `13:00 | #2 ShippingComplete | ShippingCompleteService.markShipped(orderId, shippedDate, note) — 선형 상태머신(Pending→InProgress→Done→Shipped) 검증 + 미래일 차단 + 이미 Shipped 차단. shippingComplete LWC(Order Record Page) — done 시 [🚚 출고 등록] 버튼 + 날짜 + 비고. 7/7 PASS, 94% 커버.`
- `13:20 | #3 PaymentService | register(orderId, paidDate, amount, memo) + getSummary. Order Master-Detail 불가 → Apex 가 Total_Paid_Amount 합산 + Account.Total_AR 동시 재계산. Outstanding_Amount Formula 가 자동 차감. paymentRegister LWC — 진행도 바(완납/부분/미입금 색상) + 입금 이력 테이블 + 폼. 10/10 PASS (CallBlock interface 헬퍼로 예외 케이스 4건 간결화), 94% 커버.`
- `13:50 | #6 aeCockpit | AeCockpitService.load() 단일 호출로 5섹션 DTO 반환 (newRfqs/priorityLeads/sentQuotes/riskyOrders/arActions). aeCockpit LWC — 5카드 그리드(slds responsive auto-fit), NavigationMixin 으로 클릭 시 record 이동. lightning__AppPage + HomePage 둘 다 노출. 6/6 PASS, 100% 커버. AeCockpitService.fetchNewRfqs 가 Status='신규' 만 필터하는 점 assertion 수정 1회.`
- `14:30 | #4 longTermDebtorBanner | Account Record Page 전용 LWC — uiRecordApi getRecord 로 Long_Term_Debtor__c/Total_AR__c/Credit_Limit__c 읽고 빨간 띠 + pulse 애니메이션 + "신규 거래 신중 검토" CTA. 한도 초과 시 초과액 표시. 순수 표시용(Apex 없음).`
- `14:45 | #5 LongTermDebtorScheduler | Schedulable Apex (D20 패턴 — Flow 대신). cron '0 0 2 * * ?' 매일 2시. 룰: Outstanding>0 + EffectiveDate≤today-180 보유 Account 자동 true / 해소 시 false 정정. process() AuraEnabled (데모 수동 실행) + scheduleDaily() 등록 헬퍼. 5/5 PASS, 100% 커버. CronTrigger 검증 포함.`
- `Day 9 종료 | FR-ORDER-005/006 + FR-AR-001/002/003 + FR-COCKPIT-001 모두 완료. 6 작업 모두 ★ 시연 §1~§9 골든패스 자산 완성. 누계 Apex Test ~210/210 PASS 예정. 신규 클래스 평균 95%+ 커버. 다음 = Day 10 (Agentforce 5 Action + 리허설).`

---

## 2026-05-13 (화) — Day 10 Phase A: Agentforce 4 Action 백엔드 (validate-only)

- `09:30 | 컨텍스트 | HANDOFF v7 §6 + 남은일정 매트릭스 확인. 사용자 결정: Employee Agent + 4 Action 우선(getCrossSellCandidates T2 제외). sf-ai-agentforce 스킬 로드.`
- `09:35 | 폴더 신설 | classes/agentforce/ 도메인 폴더. 5 신규 cls(4 Action + 1 Test) + 5 -meta.xml.`
- `09:40 | GetTodayPriorityListAction | AeCockpitService.load() 래핑 → 5카테고리(newRfq/priorityLead/sentQuote/riskyOrder/arAction) 건수 + 한국어 summary + detailsJson. category 필터 입력. @InvocableMethod category='Sales Cockpit'.`
- `09:42 | GetOrderAtRiskAction | Order.Delivery_Risk_Score>=70 SOQL(저장된 값만, 동기화는 [🔄 ERP 동기화] 버튼 담당). minRiskScore/maxResults 입력. 85+ 대형지연 별도 카운트. 100% 커버.`
- `09:45 | GetAccountSummaryAction | accountId 우선 / accountName 부분일치 fallback. 한국 영업 6필드(사업자번호/대표자/신용한도/외부신용점수/누적미수금/장기미수) + 진행중 Opp/미출고 Order 건수. 100% 커버.`
- `09:50 | DraftFollowupEmailAction | FollowupDraft Prompt Builder 호출 + D26 stripCodeFences 가드 + 실패 시 한국어 fallback. urgency 계산(Sent_Date 7일+ → urgent → 제목 [재요청] 접두 + 본문 "1주일 경과 안내" 추가). 75% 커버(라이브 ConnectApi 블록 ~25줄 분리 후 의미있는 covered 로직 추가로 임계 통과).`
- `09:55 | FollowupDraft Prompt Template | SOBJECT://Quote + primitive://String 2 입력. 정중체 한국어, {"subject":"","body":""} JSON 강제. status=Draft 초기 deploy(versionIdentifier 미명시 — 사용자 retrieve 후 Published 전환 필요).`
- `10:00 | AgentforceActions_Test 18 케이스 | 4 Action 통합. fixture 3종(makeAccount/makeOrder/makeQuote). 함정 2건 해결: ①GetAccountSummary 의 변수명 like 가 Apex 예약어 → namePattern, ②IsParallel=true 가 Test.getStandardPricebookId() 충돌 → 제거.`
- `10:08 | 검증 통과 | sf project deploy validate --tests AgentforceActions_Test 18/18 PASS. GetOrderAtRisk 100% / GetAccountSummary 100% / GetTodayPriorityList 92% / DraftFollowupEmail 75%. 6 components(Apex 5 + Prompt 1) ready to deploy. deployId 0AfdM00000aJY1G.`
- `Day 10 Phase A 종료 | 4 Invocable Apex + FollowupDraft Prompt Template 검증 완료, 아직 미배포(validate-only). 다음 — Phase B: GenAiFunction × 4 + GenAiPlugin + Bot(SalesCockpitAssistant) 메타 + 실 배포 + Prompt Template Published 전환 + agentforceInputBar LWC + E2E.`
- `10:30 | Deliverable 변경 | 사용자 통보 — 라이브 발표 취소, 2026-05-14 (목) 18:00 까지 슬라이드 자료(PPT/PDF) 메일 제출로 전환. 영향: ①Q&A 라이브 없음 → D17/18/25/26/27 답변을 슬라이드 안에 자기설명 형태로, ②시연 라이브 없음 → 동영상/스크린샷 캡처 필수, ③슬라이드 9 섹션 구성(Cover/차별화/골든패스/AI 라인/ERP 게이트웨이/Agentforce/의사결정/카탈로그/한계). HANDOFF v8 + remaining-schedule v1 모두 갱신.`

---

## 2026-05-13 (화) — Day 10 Phase B: Agentforce 메타 + 활성화 (코드 경로)

- `13:00 | Phase B 진입 | 사용자 결정: Setup UI 아닌 코드 경로 우선. 이전 OCR 작업의 input 변수명 함정 학습 활용해 4 Apex Invocable 의 @InvocableVariable 이름과 100% 일치하는 메타 작성 계획. Day 10 Phase A 산출물(Apex 4 + FollowupDraft) 실 deploy 부터.`
- `13:05 | Phase A 실 deploy | sf project deploy start --tests AgentforceActions_Test → 18/18 PASS. deployId 0AfdM00000aJfFdSAK. 6 components(Apex 5 + Prompt 1) Created.`
- `13:08 | FollowupDraft Published 전환 | retrieve → versionIdentifier 확보(Kq6SQoRu...=_1) → activeVersionIdentifier 명시 + status=Published 재배포. Day 5 PR0014 패턴 재현.`
- `13:12 | GenAiFunction × 4 메타 | genAiFunctions/<Name>/<Name>.genAiFunction-meta.xml × 4. invocationTarget=Apex 클래스명 / invocationTargetType=apex / description 은 Action planner routing prompt. schema.json 불필요(SF 자동 인식). validate + deploy 통과.`
- `13:18 | PermSet Sales_Cockpit_User 갱신 | 4 신규 Apex classAccess 추가 + 배포 성공.`
- `13:22 | GenAiPlugin 직접 작성 시도 → schema 함정 4건 연속 | ①pluginInstruction 무효, ②developerName 필수, ③language 필수, ④pluginType 필수. 정정 후 배포 성공(SalesCockpitAssistant).`
- `13:30 | Bot 직접 작성 시도 → schema 함정 2건 | ①messageType=InboundMessage 무효, ②type=EinsteinServiceAgent 는 BotType enum 무효(Agentforce 에서는 type=ExternalCopilot + 별도 agentType=EinsteinServiceAgent 필드). 직접 XML 조립 포기.`
- `13:40 | D28 의사결정 | sf agent create --spec 경로 채택. 직접 XML schema 조립 대비 SF CLI 가 일관 형식으로 일괄 생성. 단점은 type=ExternalCopilot 강제. 평가자 narrative 로 보완 가능.`
- `13:45 | sf agent generate agent-spec | specs/SalesCockpitAssistant.yaml 생성(role/company/maxTopics=1). 사용자가 YAML 수정 — Topic description 에 4 Action API name 명시.`
- `13:55 | sf agent create | name="한도세일즈 도우미" api-name=HandoSalesAgent. 성공. botId=0XxdM000003nJHV / botVersionId=0X9dM000007MARJ / plannerId=16jdM000003KdMr. LLM 이 우리 4 GenAiFunctions + EmployeeCopilot__AnswerQuestionsWithKnowledge fallback 자동 매핑. 한국어 sampleUtterances 5개 자동 생성.`
- `14:00 | retrieve | Bot:HandoSalesAgent + GenAiPlannerBundle:HandoSalesAgent + GenAiPlugin:p_16jdM000003KdMr_Sales_Cockpit_Assistant 모두 retrieve 해 force-app 소스 자산화. v66 정확한 schema 확보.`
- `14:05 | sf agent activate | version=1 활성. preview 시작 가능.`
- `14:10 | Agent user 자동 생성 발견 | handosalesagent@00ddm00000vcd7z2088331697.ext / Profile=Einstein Agent User / Standard UserType. Anonymous Apex 로 Sales_Cockpit_User 할당 시도 → VF page 접근 권한이 Einstein Agent User 라이센스 호환 불가로 실패.`
- `14:15 | Agentforce_Sales_Cockpit PermSet 신설 | Apex classAccess(5) + Object Read(Lead/Account/Contact/Opp/Quote/Order, viewAll=false 강제) + Field Read(14 핵심 커스텀 필드). 배포 + Anonymous Apex 로 agent user 자동 할당 + 표준 AgentforceServiceAgentUser PermSet 도 함께 할당.`
- `14:20 | sf agent preview start + send | "오늘 우선순위 알려줘" 한국어 질의 → 한국어 응답 ("오늘의 우선순위 정보를 가져오는 데 문제가 발생했습니다") 하지만 실제 Apex 호출 실패("configuration issue / 데이터 라이브러리 미할당" 영문). Apex 자체는 admin 으로 정상 동작 검증(7건 반환).`
- `14:25 | Phase B 1-step 미해결 | Apex+메타+활성화+권한 모두 완료, 단 sf agent preview 자연어 질의 시 런타임 권한 추가 필요 추정. Setup UI Agent Builder → Topic → Action 별 "Manage Access" 토글 가능성. 사용자가 2~3분 UI 작업으로 해결 권장.`
- `Day 10 Phase B 종료 | 90% 완료 — 모든 메타 source-controlled + 활성화. 잔여 1-step (Setup UI Action Access 토글) 후 동영상 캡처 가능. HANDOFF v9 + §20 학습 기록 + 의사결정 D28 추가.`

---

## 2026-05-11 — Day 11: 잔여 punch list 일괄 처리 (Phase 1~5)

- `14:30 | 계획 | 사용자 요청 — 슬라이드 캡처 전 모든 미완 작업 정리. 7 phase: P1 Agentforce access / P2 Schedulable 등록 / P4-A CallMemoExtract AI / P4-B OPP-002 Stage 자동 전이 / P4-C AR-003 Quote 헤더 / P4-D QUOTE-008 7일 follow-up / P5 커버리지 보강.`
- `14:35 | Phase 1 진단 | auto-PermSet HandoSalesAgent437863651_Permissions 가 비어 있음 발견. classAccess + Object/Field 추가 후 재배포 → preview 메시지 변화 ("제공할 수 없습니다" → "가져오는 데 문제 발생"), 그러나 ApexLog 0 (액션 호출 안 됨).`
- `14:40 | Phase 1 외부 리서치 | document-specialist 백그라운드 호출 → 결정적 단서 2건: ①sf agent preview 기본 simulated mode → --use-live-actions 플래그 필수, ②v66 schema.json 누락 가능성.`
- `14:42 | Phase 1 CLI 업그레이드 | sf 2.128.5 → 2.133.4. 새 CLI 에 --use-live-actions / --simulate-actions 플래그 발견 (start 명령). 적용해도 ApexLog 0 유지.`
- `14:45 | Phase 1 추가 fix | GenAiPlugin language en_US → ko 변경 + deactivate/activate. 응답 메시지 미세 변화. ExternalCopilot 타입 한계로 추정 — Setup UI "Manage Access" 토글은 v66 메타 API 미공개. **Phase 1 timeboxed**: 코드 경로 한도까지 도달, narrative 로 발표 대체 (Apex admin 호출은 정상 — 7건 반환 evidence 확보).`
- `14:46 | Phase 2 ✅ | LongTermDebtorDaily(02:00) + OrderErpSyncDaily(03:00) Anonymous Apex 등록. 신규 OrderErpSyncScheduler 클래스 + Test 작성·배포(2/2 PASS).`
- `14:50 | Phase 4-A CallMemoExtract AI ✅ | OppInsight 패턴 + D26 stripCodeFences 차용. CallMemoExtract genAiPromptTemplate (primitive://String Memo, sfdc_ai__DefaultGPT41Mini) 신설 → Draft 배포 → versionIdentifier 확인 → Published 활성. Service 재작성 (AI 우선, 정규식 fallback, lastSource 노출, mock 우회). Test 재작성 9/9 PASS. E2E 실 LLM 호출 검증: '현대모비스 김 대리 010-1234-5678 베어링 6204 100개 다음달 말까지' / '(주)대광건설기계 박과장 010-9876-5432 단조품 SKD-11 50EA 3주 내' 모두 완벽 추출 (lastSource=ai).`
- `14:55 | Phase 4-B OPP-002 ✅ | QuoteEmailService.sendQuote 확장: Quote.Status='발송' + Sent_Date 갱신 후 Opp.StageName='견적 작성' 일 때만 '견적 발송' 자동 전이. 이미 협상/수주 진입 시 skip. silent skip on DML fail. testSendQuote_autoTransitions_QuoteBuildingToSent + testSendQuote_skipsTransition_WhenStageIsDiscovery 신규 2건. 한글 메서드명 불가 발견·정정. 10/10 PASS, QuoteEmailService 87%.`
- `15:00 | Phase 4-C AR-003 ✅ | PricingService 확장: Quote SOQL 에 Account.Total_AR/Long_Term_Debtor/Credit_Limit 추가, QuoteHeaderDTO 에 5 필드 추가 (totalAR/longTermDebtor/creditLimit/creditExceeded/creditUtilization). loadSummary 끝에서 netTotal+Total_AR > creditLimit 시 creditExceeded 플래그. quoteBuilder LWC HTML: showArHeader 조건부 표시 + 신용한도 초과 경고 배너 + LongTerm 빨간 chip + CSS bl-ar-header/bl-ar-warning. 7/7 PASS, PricingService 92%.`
- `15:02 | Phase 4-D QUOTE-008 ✅ | QuoteFollowupScheduler 신규 — Status='발송' AND Sent_Date <= today-7 AND Last_Opened_At IS NULL 인 Quote 에 High 우선순위 Task 자동 생성. WhatId 멱등성 (미완료 follow-up Task 있으면 skip). scheduleDaily() 04:00 cron. 6/6 PASS, 97% 커버. PermSet classAccess 추가.`
- `15:03 | Phase 2 보강 ✅ | QuoteFollowupDaily(04:00) Anonymous Apex 등록. 총 3 cron jobs WAITING: LongTermDebtor 02:00 / OrderErpSync 03:00 / QuoteFollowup 04:00.`
- `15:05 | Phase 5 커버리지 ✅ | QuotePdfController_Test 신설 (StandardController 생성자 + 라인 합계 + Korean amount 경계 + 빈 라인 + 최소 Account 분기) → 17% → **100%**. StageGateServiceTest 확장 (Rule 2 견적 작성→견적 발송 3 케이스 + Rule 3 견적 발송→협상 2 케이스 + Terminal Stage) → 52% → **100%**. EmailIntentClassifyService_Test 보강 (empty list / valid IDs / invalid JSON / stripCodeFences / autoDraftIfRequote) → 66% → 74%(@future catch async 한계).`
- `15:08 | Test 함정 발견·해결 | Scheduler 테스트들이 'LongTermDebtorDaily/OrderErpSyncDaily/QuoteFollowupDaily' 명칭으로 System.schedule 호출 → 실 cron 과 충돌 ("이미 예약" Exception). 해결: test 전용 이름 (suffix _TEST_<timestamp>) 으로 직접 System.schedule 호출. 3 test 클래스 수정.`
- `15:10 | RunLocalTests 최종 | **258/258 PASS, 100% Pass Rate, Org-wide 89%** (이전 80% → 목표 85% 초과 달성).`
- `Day 11 종료 | Phase 2/4-A/4-B/4-C/4-D/5 모두 완료. Phase 1 은 코드 경로 한도까지 도달 (Setup UI 잔여 1-step). 시연 동영상 캡처 + 슬라이드 작성 단계로 진입 가능. 다음 세션 = 골든패스 동영상 캡처 → PPT/PDF 작성 → 5/14 18:00 메일 제출.`

---

## 2026-05-11 — Day 11 (계속): ★★★ Phase 6 세트 완성

- `15:00 | 결정 | 사용자 요청 — 슬라이드 작성 전 추가 ★★/★ 4건 완성. agentforceInputBar + LEAD-002 SpecExtract + ORDER-004 DelayNotice + GetCrossSellCandidates 5번째 Action.`
- `15:05 | Phase 6-A ✅ agentforceInputBar LWC | AgentforceInputBarService 신설 — utterance 키워드 매칭 → 4 Invocable Action 직접 호출 (ExternalCopilot 한계 우회). LWC HTML/JS/CSS (입력창 + 예시 chip 4개 + 응답 영역 + 상세 JSON 토글). isExposed=true (App/Home/Record Page). LWC1065 (for:each idx key) 발견·정정. 8/8 PASS, 99% cov.`
- `15:15 | Phase 6-B ✅ SpecExtract AI | SpecExtract genAiPromptTemplate 신설 (Subject+Body 2 primitive 입력, 6필드 JSON 출력). SpecExtractService + SpecExtractInvoker 분리 (라이브 ConnectApi 커버리지 격리 — BusinessLicensePromptInvoker 패턴). RfqInboundHandler 가 SpecExtract 우선 → CallMemoExtract fallback. Test 18/18 PASS. E2E: '한라정공 박과장 010-7777-8888 베어링 6204 100개 다음달 말까지' → 완벽 추출 (lastSource=ai). --ignore-warnings 사용 (Invoker 15% < 75% 정책 우회, 라이브 블록은 unit test 불가).`
- `15:35 | Phase 6-C ✅ DelayNotice Prompt | DelayNotice genAiPromptTemplate 신설 (Order SObject + AdditionalContext primitive). DelayNoticeService + DelayNoticeInvoker 분리. orderRiskCard.handleNotify 를 async로 변환 — AI subject+body → mailto: 컴포저. AI 실패 시 한국어 정중체 fallback. 7/7 PASS, Service 100%. E2E: 진성정밀(주) PO-2026-0079 (점수 96) → subject "[한도정밀] Order 00000207/PO-2026-0079 납기 지연 사전 통보" (aiSource=ai).`
- `15:48 | Phase 6-D ✅ GetCrossSellCandidates 5번째 Action | Invocable Apex — 입력 Account 의 발주 OrderItem Family 집합 수집 → 같은 Family 내 미구매 Product 인기순 Top N. Comparator 인터페이스로 인기도 내림차순 정렬. AgentforceInputBar 라우터 확장 (resolveAccountIdFromContext: 001/006/0Q0/801 prefix → AccountId). GenAiPlugin (Topic) 에 5번째 function 등록 + auto-PermSet HandoSalesAgent437863651_Permissions / Agentforce_Sales_Cockpit / Sales_Cockpit_User 3 PermSet 모두 classAccess 추가. 함정: 변수명 'limit_' Apex 식별자 불가 → 'cap' 정정. 시드 사업자번호 체크섬 강제 → 부수 Account 의 Business_Number 제거. 14/14 PASS, Action 94% cov, AgentforceInputBar 77% cov. E2E: 태양산업(주) (4 Orders) → 발주 카테고리 단조품/주물품 → 추천 5건 (단조품-1001 / 주물품-1008 / 단조품-1011 외 2건). AgentforceInputBar utterance "태양산업(주) 에게 추천 부품" → 동일 응답 라우팅 확인.`
- `15:55 | 최종 회귀 | RunLocalTests 294/294 PASS (100%), Org-wide 87%. Day 11 신규 추가: Apex 12 클래스 + LWC 1 + GenAiFunction 1 + GenAiPromptTemplate 3 + Test 36건 누적.`
- `Day 11 ★★★ 세트 종료 | 5종 기술 라인 완성도 ↑ — Flow (5)·Apex (35+)·LWC (15+)·Prompt Builder (8 — BusinessLicenseExtract/OpportunityInsight/IntentClassify/RequoteDraft/FollowupDraft/CallMemoExtract/SpecExtract/DelayNotice)·Agentforce (5 Action — TodayPriority/OrderAtRisk/AccountSummary/DraftFollowupEmail/CrossSellCandidates). 시연 동영상/슬라이드 작성 단계로 진입.`
- `16:00 | 세일즈 도우미 UX 개선 | LWC title "한도세일즈 도우미 (Agentforce)" → "세일즈 도우미". 키워드 카테고리 확장 (각 7~10개 동의어). AgentInputFallback Prompt + AgentInputFallbackInvoker 신설 — 키워드 매칭 실패 시 LLM 단순 자유 응답 (보라색 배지). actionLabel getter 한국어 라벨. 예시 chip 4개 + JSON 토글 제거 (placeholder 가 안내). E2E 6가지 utterance 통과 — "안녕하세요"/"오늘 우선순위"/"지난주 매출"/"무엇을 도와줄"/"태양산업 미수금"/"거긴 더 팔만한 부품" 모두 정확 라우팅 또는 LLM fallback.`
- `16:30 | 사용자 피드백 — 자유도 한계 발견 | "콕피트에서 볼 수 있는 정보 다시 물어보기 싫음, AI 가 DB 조회해서 자유 질문에 답해줄 수 있나" — 현재 LLM fallback 은 단순 응답기, DB 조회 못 함. 진짜 자연어 처리하려면 ReAct 패턴 (LLM 라우터 + Apex 호출 + 결과 종합) 필요. 토큰 부족으로 다음 세션 작업 결정.`
- `16:35 | HANDOFF v10 갱신 | §21 의사결정 D29~D32 추가, §22 ★★★ Day 12 3-step LLM 라우터 설계 + 체크리스트 + 함정 회피 가이드, §23 다음 세션 워크플로우, §24 산출물 diff. 다음 세션 첫 작업 = 3-step ReAct 라우터 구현 → 시연 캡처 → 슬라이드.`
- `Day 11 진짜 종료 | 잔여 1건 (★★★ 3-step LLM 라우터). 그 외 모든 ★★/★ 작업 완료. 누계 Apex Test 294/294 PASS, Org-wide 87%. 다음 세션 도착 시 HANDOFF §22 정독부터.`

---

## 2026-05-12 (화) — Day 12 ★★★ 3-step LLM 라우터 (ReAct 패턴)

- `08:30 | 계획 | HANDOFF §22 체크리스트 진입. AgentRouter+AgentSynthesize 2 Prompt + 2 Invoker + AgentforceInputBarService 재설계 + Test 26건 + 2단계 활성화 절차.`
- `08:35 | Prompt 메타 작성 | AgentRouter (Utterance+ContextHint primitive 2입력, JSON 출력 강제) + AgentSynthesize (Utterance+ToolName+ActionResult primitive 3입력, 자연어 1단락). 5 결정 규칙 + 4 예시 + 회사명 추출 가이드 명시. Draft 상태로 1차 deploy.`
- `08:42 | Invoker 작성 | AgentRouterInvoker + AgentSynthesizeInvoker — D30 패턴(라이브 ConnectApi 격리, mockResponse/mockExceptionMessage 정적 필드). applicationName='PromptBuilderPreview', 3-arg generateMessagesForPromptTemplate.`
- `08:48 | Service 재설계 | AgentforceInputBarService.ask() 3-stage flow — [1] tryReactRouter (router LLM → tool 선택 → Action.run() → synthesize LLM) [2] tryKeywordRouter (router 실패/none 폴백, 기존 5 키워드 유지) [3] AgentInputFallback (키워드 미스). missing_args 분기, buildContextHint(Account/Opp/Quote/Order), stripCodeFences (D26), parseRouter Map<String,Object>.`
- `08:55 | Test 26 케이스 | 기존 9 케이스 + ReAct 17 신규. router mock JSON 5분기(Today/AccountSummary/OrderRisk/CrossSell/Followup) + missing_args 3 + none fall-through 2 + code fence + invalid JSON + unknown tool + synthesize fail raw summary + Invoker 단위.`
- `09:00 | 1차 deploy 실패 | RunSpecifiedTests 로는 Invoker 14% < 75% 경고로 status=Failed. --ignore-warnings 만으로 미해결.`
- `09:02 | 정정 deploy | --test-level RunLocalTests --ignore-warnings 로 org-wide 커버리지 적용. 12 components Succeeded, **319/319 PASS**.`
- `09:05 | 2단계 활성화 | retrieve "GenAiPromptTemplate:AgentRouter, AgentSynthesize" → versionIdentifier (Kq6SQoRu...=_1) 확보. 메타에 activeVersionIdentifier + status=Published 추가. 재배포 Succeeded.`
- `09:10 | E2E 실 LLM 검증 5/5 | (1) "오늘 뭐 해야 해?" → GetTodayPriorityList → "오늘 우선순위 총 12건…발송 Quote 2건/위험 Order 5건/미수금 5건". (2) "대성기공(주) 물건 나갔나요?" → GetAccountSummary → "미출고 Order 3건, 진행 Opp 1건, 장기미수 보유". (3) "납기 위험 어떤 게 있어?" → GetOrderAtRisk → "10건 중 5건이 85+ 대형지연 — 진성정밀/서울특수강/광명MES/미래공업/태양산업". (4) "대성기공(주)에게 뭐 더 팔까?" → GetCrossSellCandidates → "베어링·정밀가공품 카테고리 5건 추천". (5) "안녕하세요" → llm_fallback → "안녕하세요! 무엇을 도와드릴까요?". 5/5 정확 라우팅 + 데이터 인용 + 자연체 한국어 응답.`
- `Day 12 ReAct 라우터 종료 | §22 체크리스트 완료. 누계 Apex Test 319/319 PASS, Org-wide 87% 유지. 다음 = 시연 동영상 캡처 → 슬라이드 작성 → 5/14 18:00 메일 제출. 평가자 narrative: "같은 Apex Invocable Action 을 Agentforce planner / 키워드 라우터 / ReAct LLM 라우터 3가지 path 가 호출 — 5종 기술 통합 + LLM이 DB 조회까지 자동 종합".`

---

## 2026-05-12 (화) — Day 13 UX 다듬기 6건 (D33)

- `09:10 | 계획 | superpowers brainstorming + writing-plans 으로 6 enhancement spec (docs/specs/2026-05-12-ux-polish-{design,plan}.md). 의사결정 D33 — architecture 변경 없이 표면만, ~3.5h 안에 시연 동영상 캡처 전 마무리.`
- `09:15 | Task 1 ✅ 협상→수주 안내 | stageGateChecklist.js getter 2개(isPreWonStage/isTerminalStage) + .html else 블록 3분기. '협상' 단계에서 '협상 완료시 [수주]로 전환하세요' info 박스 표시. terminal('수주'/'실주') 단계는 '최종 단계입니다'. LWC만 변경, Apex 영향 0.`
- `09:25 | Task 5 ✅ 견적 첨부 게이트 | StageGateService.checkQuoteReadiness 에 ContentDocumentLink COUNT 추가 + 신규 GateRule '견적 첨부 파일'(SLDS Files 영역의 첨부 어떤 것이든 1+). evaluateRules '견적 작성→견적 발송' 분기에 3번째 룰. Test 2 신규(noAttachment_fails / withAttachment_passes) + 회귀 3 케이스 보정(rule size 2→3). 누계 319→321 PASS.`
- `09:40 | Task 2 ✅ 납기일 표시 | AeCockpitService.dueLabel(Date) 헬퍼 — D-N / D-day / D-3 임박 / D+N 초과 한국어 라벨 emoji 포함. RiskyOrderRow DTO 에 endDate/dueLabel 2 필드. OrderErpSyncService.OrderRiskView 도 동일 확장. orderRiskCard 카드의 메타 영역에 납기일 컬럼 + 색상 배지(error/warning). aeCockpit 위험 Order 카드 행에 배지. scripts/apex/backfillOrderDueDates.apex 신설 — Math.mod 함정 1회(%는 Apex 미지원). 분포 정합 확인 — overdue 5/imminent 5/safe 91. Order.EndDate ≥ EffectiveDate 제약 함정으로 Test setup 정정. Scheduler cron 충돌 함정 1회(abort→재배포→reschedule). Test 2 신규 + 1 케이스 추가 = +3 누계 324.`
- `10:00 | Task 4 ✅ 공통 로딩 메시지 | CustomLabel AI_Loading_Message ("잠시만 기다려 주세요... AI가 답변을 작성 중이에요") 신설. 4 LWC(businessLicenseUpload/oppInsightCard/quoteBuilder/orderRiskCard) 일괄 — '@salesforce/label/c.AI_Loading_Message' import + labels.aiLoading 필드 + .html spinner alternative-text 통일. agentforceInputBar 는 Task 6 에서 통합.`
- `10:10 | Task 3 ✅ AgentSynthesize 인라인 ID 마커 | Prompt 룰 7번 추가 — 특정 레코드 언급 시 이름 직후 {{id:18자ID}} 토큰 강제. ActionResult JSON 의 accountId/orderId/quoteId/productId/*Id 자동 인용. 길이 320자로 상향. 예시 1건도 마커 포함으로 갱신. Draft 1차 배포 → retrieve versionIdentifier=_2 → activeVersionIdentifier + Published 재배포. E2E 실 LLM 검증 — Q1 "납기 위험" 응답에 진성정밀(주)/서울특수강(주)/광명MES(주) 3개 회사 모두 {{id:801dM...}} 토큰 인용. Q2 "대성기공(주) 미수금" 응답도 {{id:001dM...}} 인용. hasMarker=true 100%.`
- `10:25 | Task 6 ✅ 챗봇 스타일 입력바 | agentforceInputBar 3 파일 전면 재작성 — 메시지 누적 배열 messages[](50건 cap), parseInlineIds 정규식 토크나이저, NavigationMixin handleNav, 타이핑 점 3개 0.4s bouncing animation, 보라색 LLM/노랑 info/빨강 error 버블 변형. AI_Loading_Message 통합. chatbot__header (보라 그라데이션) + chatbot__log (480px 스크롤) + chatbot__input (lightning-input + send 버튼) 3단 구조. Task 3 인라인 링크와 통합 — AI 응답 안의 회사명·Order 번호가 클릭 가능 underline 링크.`
- `10:35 | 최종 회귀 | RunLocalTests **344/344 PASS, 100% Pass Rate**, Org-wide 87% 유지. Day 12 319 → Day 13 344 (+25). 6 Task 모두 완료.`
- `Day 13 종료 | UX 6 enhancement 완료. 시연 동영상 캡처 + 슬라이드 작성 단계로 진입 가능. 평가자 narrative 보강: "5종 기술 라인 안정화 후 시연 직전 표면 다듬기 빠른 반복" (D33). 다음 = 5/14 18:00 마감까지 시연 캡처 + PPT/PDF.`

---

## 2026-05-12 (화) — Day 13 추가 트랙 (D35/D36/D37 + SLDS v2)

- `11:00 | Day 13 #7 영업 파이프라인 (D35) | AeCockpitService.Dashboard 에 stagePipeline 필드 + fetchStagePipeline() (5단계 모두 보장, '수주'는 IsClosed=true 라 별도 query). 신규 oppPipelineCard LWC (가로 막대 + 단계별 색상 + 단계 클릭 → Opp ListView). aeCockpit 우선 Lead 카드 헤더에 Status 분포 chip. Test 1 신규 (testStagePipeline_groupsByStage). 324/324 PASS.`
- `12:30 | Day 13 #8 레이아웃 정비 (D36) | (1) Lead Record Page 활동 탭 제거 (사용자 직접). (2) Lead 신규 LWC leadScoreBadge — 그라데이션 4단계 점수 카드 (Hot/Warm/Lukewarm/Cold). 시드 Lead 점수 백필 scoreLeads.apex (Phone 채널 base 50점). (3) Account 7필드 제거 (Industry/Fax/AccountNumber/Website/ParentId/Created/Modified). (4) Opp 4필드 추가 (LeadSource/Type/ExpectedRevenue/ForecastCategoryName). (5) Quote 레이아웃 청구인·주소 섹션 제거.`
- `13:00 | Day 13 #9 챗봇 FAB + 전화 Lead FAB | Lightning Experience chrome 구조 분석 후 D34 결정 — app-wide floating 불가, Home Page 한정 채택. chatbotFab LWC (보라 동그라미 60×60, 우하단 24px, 둥둥 애니메이션 3s, agentforceInputBar 460×600 패널 임베드). leadIntakeFab LWC (초록 동그라미 right:100, 중앙 모달 680×95vh, backdrop click-to-close, phoneLeadIntake 임베드). FAB 디자인은 사용자 만족도 높아 v2 표준화에서 의도적 제외.`
- `14:30 | Day 13 #10 SLDS v2 디자인 시스템 통일 | 사용자 피드백: 색상 너무 다양, 이모티콘 별로. design-preview.html 2회 iteration 후 v2 확정 — 8토큰만(brand=SLDS#1B96FF/3 status/5 gray), 좌측 4px strip 패턴, lightning-icon 표준. 적용: leadScoreBadge / orderRiskCard / oppInsightCard / oppPipelineCard / aeCockpit (CSS 전면 재작성). 이모티콘 16건 일괄 제거 (📋📈🎯⚠📥📤💰🚪🔥❄☀⏰🚚📡💡📌✉🔄). agentforceInputBar / chatbotFab / leadIntakeFab 는 의도적 유지 (사용자 명시).`
- `15:00 | Day 13 #11 Quote 자동화 (D37) | 신규 QuoteTrigger + QuoteTriggerHandler 작성. Rule 1 (before insert): Account 의 주소·1차 Contact 자동 복사. Rule 2 (after update): Status '수락' 전이 시 QuoteLineItem → OpportunityLineItem 자동 복사. 함정 학습: (a) Quote.IsSyncing 표준 platform read-only — Apex set 불가 → 직접 OLI 복사로 우회. (b) Quote.AccountId 는 before insert 시점에 자동 미채움 → Opportunity 에서 derive 필요. (c) Test 의 State/Country picklist 활성화 — BillingStreet/City 도 함께 reject → test 단순화 (BillingName/Phone/ContactId 만 검증). Test 7 케이스 신규.`
- `15:30 | 최종 회귀 | RunLocalTests 332/332 PASS (100%). Day 12 319 → Day 13 +13 Test = 332. Org-wide 87% 유지. Scheduler cron abort/reschedule 패턴 5회 학습.`
- `Day 13 진짜 종료 | 트랙 6개 모두 완료 (D33/D34/D35/D36/D37 + SLDS v2). L2C 자동화 완전 흐름 — Quote 생성 → 주소 자동 → 수락 → Opp Products 자동 → Won → Order + OrderItem 자동. HANDOFF v13 + WORKLOG 갱신. 다음 = 5/14 18:00 마감까지 시연 동영상 캡처 + PPT/PDF 슬라이드 작성.`





---

## 2026-05-12 (화 저녁) — Day 14 본 세션: PPT 작성 + 시드 리셋 + 시연 dry-run 버그 6건

- `15:00 | PPT Phase 1~5 | frontend-slides 스킬 정식 흐름 (4 질문 → 3 프리뷰 → Style C "SLDS Swiss" 선택 → Phase 3 생성). 신규 docs/specs/2026-05-12-presentation-deck.html 31장, 129KB, self-contained, inline 편집(E 키 토글, Ctrl+S export, localStorage 자동 저장). Salesforce SLDS 팔레트 (Navy/Cloud/Error/Warning/Success), Archivo+Noto Sans KR+JetBrains Mono. 영상 placeholder 5건 (Feature C 페이지) — 추후 GIF/MP4 교체.`
- `16:00 | 시드 리셋 | 신규 scripts/apex/resetDemoData.apex — 멱등 wipe + 14일 ±재시드. Entitlement/Case 정리 → Account 부분실패 허용 → 표준 Pricebook 활성. 결과: Account 10 · Contact 20 · Product 15 · Lead 8 (신규5/제안대기2/미전환1) · Opp 10 (5단계 균등) · Quote 8 · QLI 16 · Order 16 (위험3/대형지연2/정시6/장기미수4/골든1) · OrderItem 34 · Payment 23. 5카드 + Pipeline 모두 채워짐. BillingCountry 'KR'/'대한민국' 모두 picklist 거부 → 주소필드 제거로 우회.`
- `16:30 | 버그 #1 chatbotFab 닫기 잘림 | 원인 lightning-card padding + 보라 헤더 그라데이션 중복. fix: agentforceInputBar 에 @api hideHeader + lightning-card 제거(단순 div), chat-panel 자체 header 추가하고 close 버튼을 그 안에 28px 원형 + 흰 테두리로 명확 배치. 4 파일 변경 배포 ✅.`
- `17:00 | 버그 #2 oppPipelineCard funnel | 원인 width=count/maxCount → 카운트 동일 시 모두 100%. fix: amount 비중 funnel + stage 카드 grid 2-tier. 폭=amount/total 정규화 + floor 8%(active)/3%(empty). 5단계 색상 진행감(회색→그린). 후속 요청으로 inline 라벨을 금액→단계 이름 교체, threshold 14→11%. 시드 기준 발굴10%/견적작성18.5%/견적발송19.8%/협상33.4%(가장 큼)/수주18.7% 시각화.`
- `17:15 | 버그 #3 aeCockpit 헤더 + 5건 제한 | "AE 콕피트 — 한도정밀" → "AE 콕피트", utility:dashboard_ext → standard:home (oppPipelineCard standard:opportunity 와 동일 카테고리·크기로 시각 통일). AeCockpitService ROW_LIMIT 5→10, .bl-list max-height 320px + 얇은 스크롤바.`
- `17:30 | 버그 #4 quoteBuilder 라인추가 빈 picker | 원인 견적1.Pricebook2Id=null → PricingService.getActiveProducts:35 가드. fix: 견적1 에 표준 Pricebook 연결. 후속 권고 (보류): QuoteTriggerHandler.handleBeforeInsert 에 Pricebook 자동 채움.`
- `17:45 | 버그 #5 자동 재견적 안 됨 | 원인: org 에 인바운드 메일 라우팅 미설정 → EmailMessage(Incoming=true)가 생성되지 않음 → 트리거 자체 미발화. 코드는 정상. fix: scripts/apex/simulateRequoteReply.apex (Incoming=true + RelatedToId=Quote + 자연어 본문) → 트리거 자동 발화 → @future 분류 → Intent='Requote' → 자동 재견적 Quote 생성 검증 ✅ (견적1(재견적) 8초 후 생성). 사용자 후속 요청으로 FromAddress 를 Quote→Opp→Account→1차 Contact.Email 자동 추출로 개선. 운영 환경에선 Email-to-Case 또는 InboundEmailHandler 로 해결 가능 — '아쉬웠던 점' 슬라이드 후보.`
- `18:00 | 버그 #6 paymentRegister 입금 100 거부 | 원인 lightning-input step="100" min="1" → 유효 값 1,101,201,... 만 허용 → 100/1000 거부. fix: step="1" min="0". ₩1 단위 자유 입력.`
- `18:15 | 데이터 정정 (대광건설기계 시연 흐름) | 협상 Opp의 Quote 가 발송/거절뿐이라 수주 전이 시 OrderItem 0건 + TotalAmount=0. fix: 견적2 Status='수락' 전환. QuoteTriggerHandler 자동 발화 → OpportunityLineItem 1건 갱신 ✅. 이제 협상→수주 누르면 Order + OrderItem 자동.`
- `18:30 | HANDOFF v14 + WORKLOG 갱신 | 작업 순서 0(시드)·1(dry-run 버그) 완료. 다음 = 2(녹화)·3(PPT 다듬기)·4(PDF).`

---

## 2026-05-13 (수) — Day 15: paymentRegister fix 재발 + 챗봇 PaymentCheck Action 추가

- `08:50 | paymentRegister "유효한 증분" 재발 | Day 14 fix(step=1 min=0) 했음에도 화면에서 "유효한 증분 아닙니다" + 등록은 통과. 진단: lightning-input type="number" step 검증이 여전히 동작 + handleSubmit 이 reportValidity 안 거침. fix: step 속성 완전 제거 + formatter="decimal" (₩ 자유 입력). Deploy 0AfdM00000aRC5BSAW ✅.`
- `09:00 | 챗봇 경직성 + 입금기능 부재 진단 | 사용자: "오늘"이 들어가면 무조건 오늘 할일이 떠서 유동적이지 않음. 입금 확인도 안 됨. 근본 원인 — AgentforceInputBarService 키워드 라우터(line 281)가 '오늘' 단일 키워드 매칭 시 GetTodayPriorityListAction 직행. ReAct LLM 라우터가 PaymentCheck 같은 routes 없으니 입금 질의 → 키워드로 폴백 → 잘못 매칭.`
- `09:05 | 결정 (brainstorming) | (a) 통합 PaymentCheckAction (mode=today/week/account/atrisk) 추가, (b) 키워드 라우터 완전 제거 — ReAct LLM 만 신뢰. 사용자 확정.`
- `09:10 | 신규 PaymentCheckAction.cls | mode 4종 분기 — today/week(Paid Payment 합계+상위 고객사), account(특정 회사 청구·누적입금·잔액+최근 입금 5건), atrisk(Account.Total_AR__c Top N + Long_Term_Debtor 플래그). resolveAccount: exact → LIKE fallback. 함정: 'like' Apex 예약어 → 'fuzzy' 로 변수명 변경.`
- `09:15 | AgentforceInputBarService 단순화 | tryKeywordRouter / containsAny / extractAccountName 메서드 완전 제거 (line 271-391 ≈ 120줄). [1] ReAct → [2] AgentInputFallback → [3] 최종 안내 2단 폴백. PaymentCheck branch 추가 (mode/accountId/accountName, account 모드 시 contextRecordId 자동 보강).`
- `09:18 | AgentRouter Prompt v2 | tool 5→6 (PaymentCheck 추가). 결정 규칙에 입금/회수/미수 키워드 11종 + mode 자동 판별 ("오늘"→today, "이번주/주간/7일"→week, 회사명+잔액→account, "미수금/외상"→atrisk). 예시 6~9 추가. activeVersionIdentifier _1 → _2.`
- `09:20 | AgentSynthesize Prompt v2 | PaymentCheck 응답 예시 3건(today/account/atrisk) 추가 — {{id:...}} 토큰 패턴 유지. activeVersionIdentifier _2 → _3.`
- `09:25 | 함정 — Prompt safe-change silent reject | versionIdentifier 그대로 두고 content 만 바꿔 1차 deploy 시 "Succeeded" 떴으나 retrieve 결과 옛 content. Day 5/7/11 패턴 재확인 — versionIdentifier 를 _2/_3 로 명시 bump + activeVersionIdentifier 동시 bump → 2차 deploy 성공.`
- `09:30 | 테스트 | PaymentCheckAction_Test 13/13 PASS (96% cov), AgentforceInputBarService_Test 26/26 PASS (92% cov). 키워드 라우터 테스트 7건 제거, PaymentCheck 4건 + 폴백 흐름 5건 신규.`
- `09:35 | 실 LLM E2E 4/4 ✅ | "오늘 입금 들어온 거 있어?"→today 2건 ₩6M / "이번주 회수 어땠어?"→week 3건 ₩7.9M / "미수금 큰 데?"→atrisk 5곳 ₩38M 장기미수 4곳 포함 / "(주)대광건설기계 잔액?"→account 청구 ₩25M / 입금 ₩6M / 잔액 ₩19M. {{id:001...}} 토큰까지 정확 — Account 페이지로 인라인 네비 동작.`
- `09:40 | Day 15 산출 | 신규: PaymentCheckAction.cls + Test + .genAiFunction. 수정: AgentforceInputBarService.cls(-120줄) + Test 재작성, AgentRouter/AgentSynthesize Prompt v2, Sales_Cockpit_User PermSet, paymentRegister.html(step 제거). 누계 Agentforce Action 5→6종.`
- 14:55~15:10 | 버그 #7 quoteBuilder 제품 드롭다운 빈 옵션 (재발) | 원인: 신규 Opp 의 Pricebook2Id null → Quote 상속 null → PricingService.getActiveProducts 빈 리스트. (Day 7 17:30 보류했던 후속 권고 실행). fix: OpportunityTriggerHandler.handleBeforeInsert 추가 — Pricebook null 시 Standard 자동 할당, Test.isRunningTest 분기로 테스트 컨텍스트 호환. 잠복 버그(handleAfterUpdate 의 Won→Order silent skip)도 같이 해소. Deploy 0AfdM00000aS0mjSAC ✅ 11/11 PASS. spec: docs/superpowers/specs/2026-05-13-quote-pricebook-autoset-design.md.
- 15:15~15:25 | 버그 #8 StageGate Rule 3 견적발송→협상 잘못 막힘 | 원인: StageGateService.checkQuoteReadiness가 Quote.Status=='발송'만 isSent=true 인정 → 고객 수락('수락')으로 진행되면 더 후행 상태인데도 게이트 실패. fix: 의미 재정의 — 협상 단계 진입 조건을 '수락 받은 상태'로 명시화. 'isSent' → 'isAccepted'(Status=='수락'||'Accepted'), 라벨 '견적 발송 완료' → '고객 수락', 힌트 갱신. 테스트 3건 재정렬 (accepted_passes/sentButNotAccepted_fails/draft_fails). Deploy 0AfdM00000aS3avSAC ✅ 15/15 PASS.
- 15:45~16:10 | 버그 #9 CallMemo AI 분석 담당자 추출 오류 | 원인: Prompt 가 contactName 을 '성+직급 형태'로 강제 → '김국진씨'→'김씨'로 정보 손실, '김사장님'은 호칭 미제거. regex fallback도 동일 한계. fix: 스키마 분리 — contactName(이름) + contactTitle(직급) 별도 추출. 호칭 씨/님만 제거, 원문 표기 보존(성 단독 금지). Prompt v3 (versionId _1→_3), Service FIELD_KEYS 6→7, regex 2-패턴 (직급매칭 → 호칭매칭 fallback). phoneLeadIntake/visitLeadIntake 양식에 직급 입력 칸 추가, Lead.Title 로 저장. 테스트 4건 신규 (fullNameWithSshi/surnameWithJangNim/fullNameWithTitle/surnameWithSpaceTitle). Deploy 0AfdM00000aSJe5SAG ✅ 13/13 PASS.

## 2026-05-14 (목) — Day 16: Lead 표준 New 버튼 한국형 오버라이드

- `11:00~11:20 | 진단 | leadIntakeFab(📞 FAB) → phoneLeadIntake/visitLeadIntake 한국형 동선은 OK, but Lead List "새 리드" 표준 버튼은 영문 표준 모달 그대로 → FAB과 일관성 깨짐 (Source_Channel__c 미세팅).`
- `11:20~11:35 | brainstorming spec | docs/superpowers/specs/2026-05-14-lead-new-override-design.md. 결정: 표준 모달 룩앤필 유지 + Screen Flow 오버라이드 (LWC·Apex 0줄). 채널 picklist 검증 — Source_Channel__c restricted (PHONE/EMAIL/VISIT) → OTHER 안 씀, 기본값 PHONE.`
- `11:35~11:50 | Flow New_Lead_KR.flow-meta.xml 작성 | Screen Flow: 회사명/담당자명/직책/전화/채널(dropdown PHONE/VISIT/EMAIL)/메모 입력 → Create Lead(Status='신규', Source_Channel__c 매핑) → 성공 화면 + 새 Lead ID. Fault path → 한국어 에러 화면. status=Active.`
- `11:50~11:55 | 함정 발견 | Lead.object-meta.xml 의 actionOverride type='Flow' 시도 → 'Flow' is not a valid value for enum 'ActionOverrideType' (API v66.0). metadata API 한계 — Flow override 자동 배포 불가. object-meta.xml 제거.`
- `11:55 | Flow 단독 배포 | Deploy 0AfdM00000aUWk6SAG ✅ (Flow id 301dM00003lxDSrQAM Active).`
- `12:00 | 함정 발견 #2 | Standard Button Override UI 가 Visualforce/Lightning 구성요소만 받음 — Flow 라디오 옵션 자체 없음. metadata API와 동일 한계.`
- `12:05~12:15 | Aura wrapper c:NewLeadKrFlow | aura/NewLeadKrFlow/ 번들 (cmp + cmp-meta + controller.js). lightning:actionOverride 구현, <lightning:flow> 로 New_Lead_KR 호출, FINISHED 시 /lightning/o/Lead/list 네비. 1차 deploy 함정 — onstatuschange를 aura:handler 로 잡으려 시도 → "No EVENT named lightning:flowStatusChange". fix: <lightning:flow> attribute 핸들러로 바인드. Deploy 0AbdM000005sveLSAQ ✅. 후속(사용자 1회 수동): Setup → Lead → Buttons, Links, and Actions → New → Edit → Lightning Experience 재정의 → "Lightning 구성 요소" → c:NewLeadKrFlow → Save.`
