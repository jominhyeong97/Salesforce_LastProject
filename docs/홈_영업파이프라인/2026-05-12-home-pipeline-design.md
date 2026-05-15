# Day 13 #7 — 홈 영업 파이프라인 + 리드 대기 분포

**작성**: 2026-05-12
**목표**: 영업 진행도(Opp Stage Funnel) + 리드 대기 상태(Status chip) 시각화 추가
**시간**: ~1.5h
**의사결정**: D35

---

## 1. Opp 파이프라인 카드 (신규 LWC)

### Apex (AeCockpitService 확장)
- `Dashboard` DTO 에 `stagePipeline: List<PipelineStage>` 필드
- 신규 inner class `PipelineStage`:
  ```apex
  public class PipelineStage {
      @AuraEnabled public String stageName;
      @AuraEnabled public Integer oppCount;
      @AuraEnabled public Decimal totalAmount;
      @AuraEnabled public Integer order;  // 1~5, 시각화 순서
  }
  ```
- 신규 fetcher `fetchStagePipeline()`:
  ```apex
  private static List<PipelineStage> fetchStagePipeline() {
      Map<String, Integer> stageOrder = new Map<String, Integer>{
          '발굴'=>1, '견적 작성'=>2, '견적 발송'=>3, '협상'=>4, '수주'=>5
      };
      Map<String, PipelineStage> byStage = new Map<String, PipelineStage>();
      for (AggregateResult ar : [
          SELECT StageName s, COUNT(Id) cnt, SUM(Amount) amt
          FROM Opportunity
          WHERE IsClosed = false AND StageName != null
          GROUP BY StageName
      ]) {
          String s = (String) ar.get('s');
          if (!stageOrder.containsKey(s)) continue;  // '실주' 제외
          PipelineStage p = new PipelineStage();
          p.stageName = s;
          p.oppCount = ((Long) ar.get('cnt')).intValue();
          p.totalAmount = (Decimal) ar.get('amt');
          if (p.totalAmount == null) p.totalAmount = 0;
          p.order = stageOrder.get(s);
          byStage.put(s, p);
      }
      // 각 단계 보장 (없으면 0 으로)
      List<PipelineStage> out = new List<PipelineStage>();
      for (String s : new List<String>{'발굴','견적 작성','견적 발송','협상','수주'}) {
          if (byStage.containsKey(s)) out.add(byStage.get(s));
          else {
              PipelineStage z = new PipelineStage();
              z.stageName = s; z.oppCount = 0; z.totalAmount = 0;
              z.order = stageOrder.get(s);
              out.add(z);
          }
      }
      return out;
  }
  ```

### LWC oppPipelineCard
- 4 파일: `.html`, `.js`, `.css`, `.js-meta.xml`
- `@wire load` (AeCockpitService.load 재사용)
- HTML: 5단계 가로 막대 — 단계명 / 막대 width=count/max×100% / count + amount(만원)
- 클릭 핸들러: NavigationMixin `standard__objectPage` Opportunity list (filter by stage 없으면 default recent)
- 데이터 0 인 단계도 회색 막대로 자리 보존

### CSS 패턴
- 발굴=#9ca3af, 견적 작성=#3b82f6, 견적 발송=#06b6d4, 협상=#f59e0b, 수주=#22c55e
- transition: width 0.6s ease 로 첫 로드 시 막대 grow 애니메이션

## 2. Lead Status chip (aeCockpit 확장)

### aeCockpit.js
- 신규 getter `leadStatusBreakdown`:
  ```js
  get leadStatusBreakdown() {
      const map = {};
      (this.dashboard?.priorityLeads ?? []).forEach(l => {
          map[l.status] = (map[l.status] || 0) + 1;
      });
      return Object.keys(map).map(s => ({
          key: s, label: s, count: map[s]
      }));
  }
  ```

### aeCockpit.html
- "🎯 우선 처리 Lead" 카드 헤더 직후 chip 영역 추가:
  ```html
  <template lwc:if={leadStatusBreakdown.length}>
      <div class="bl-chip-row">
          <template for:each={leadStatusBreakdown} for:item="c">
              <span key={c.key} class="bl-chip">{c.label} {c.count}건</span>
          </template>
      </div>
  </template>
  ```

### aeCockpit.css
- `.bl-chip-row { display: flex; gap: 0.3rem; margin-bottom: 0.4rem; }`
- `.bl-chip { background: #eef2ff; color: #4b46c2; padding: 0.1rem 0.5rem; border-radius: 0.5rem; font-size: 0.72rem; }`

## 3. Test

### AeCockpitService_Test
- `testStagePipeline_groupsByStage`:
  - setup 3 Opp at 발굴 / 2 at 견적 작성 / 1 at 협상
  - assertEquals counts [3, 2, 0, 1, 0]
  - 5 stages 보장

## 4. 배포 + UI

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/cockpit \
  --source-dir force-app/main/default/lwc/oppPipelineCard \
  --source-dir force-app/main/default/lwc/aeCockpit \
  --target-org My_Org --ignore-warnings --test-level RunLocalTests
```

App Builder Home Page → oppPipelineCard 드래그 → aeCockpit 위 또는 옆 배치.

## 5. 위험

- StageName NULL Opp 가 있어도 fetcher 가 WHERE 절로 제외 — 안전
- Amount NULL → COALESCE 0 처리
- ListView filter 미존재 시 default Opp listview 로 fallback
- Scheduler cron 충돌 — 이미 Day 13 에서 abort/reschedule 패턴 학습. RunLocalTests 사용
