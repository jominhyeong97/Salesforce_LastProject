import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import load from '@salesforce/apex/AeCockpitService.load';

// 단계별 진행 색상 (회색 → 블루 → 딥블루 → 오렌지 → 그린)
const STAGE_COLOR = {
    '발굴':       '#B0ADAB',
    '견적 작성':  '#5BA3F0',
    '견적 발송':  '#0176D3',
    '협상':       '#FE9339',
    '수주':       '#2E844A'
};

// funnel width 계산 — 카운트 있는 단계는 최소 8%, 없으면 3% 빈 슬롯
const MIN_PCT_ACTIVE = 8;
const MIN_PCT_EMPTY  = 3;

// funnel 세그먼트 안에 단계 이름(예: 발굴 / 견적 작성) 표시할 최소 폭
// 한국어 2~4자 라벨은 11% 정도부터 한 줄에 들어감
const INLINE_LABEL_THRESHOLD_PCT = 11;

export default class OppPipelineCard extends NavigationMixin(LightningElement) {

    wiredResult;
    dashboard;
    errorMessage = '';
    isLoading = true;

    @wire(load)
    handle(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.dashboard = result.data;
            this.errorMessage = '';
        } else if (result.error) {
            this.errorMessage =
                result.error.body?.message || result.error.message || '조회 실패';
        }
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredResult).finally(() => { this.isLoading = false; });
    }

    get hasPipeline() {
        return !!(this.dashboard && this.dashboard.stagePipeline);
    }

    /**
     * pipeline 행 가공 — funnel(amount 비중) + stage 카드 둘 다에 쓰임
     *
     * width 계산:
     *   1) raw% = amount / totalAmount × 100
     *   2) floor: oppCount>0 면 MIN_PCT_ACTIVE, 아니면 MIN_PCT_EMPTY
     *   3) 합계 100% 가 되도록 정규화 (scale = 100 / sum)
     */
    get pipelineRows() {
        const stages = this.dashboard?.stagePipeline ?? [];
        if (!stages.length) return [];

        const totalAmount = stages.reduce(
            (sum, s) => sum + (Number(s.totalAmount) || 0), 0
        );

        // 1단계 — raw % + floor 적용
        const withFloor = stages.map(s => {
            const amt = Number(s.totalAmount) || 0;
            const raw = totalAmount > 0 ? (amt / totalAmount * 100) : 0;
            const floor = s.oppCount > 0 ? MIN_PCT_ACTIVE : MIN_PCT_EMPTY;
            return {
                stage: s,
                pct: Math.max(raw, floor)
            };
        });

        // 2단계 — 정규화 (sum → 100%)
        const sum = withFloor.reduce((s, r) => s + r.pct, 0);
        const scale = sum > 0 ? 100 / sum : 0;

        return withFloor.map(r => {
            const s = r.stage;
            const finalPct = r.pct * scale;
            const color = STAGE_COLOR[s.stageName] || '#999';
            const isEmpty = !s.oppCount;

            return {
                stageName:    s.stageName,
                stageOrder:   s.stageOrder,
                oppCount:     s.oppCount || 0,
                totalAmount:  s.totalAmount,
                amountText:   this.formatAmount(s.totalAmount),
                amountShort:  this.formatAmountShort(s.totalAmount),
                tooltip:      `${s.stageName} — ${s.oppCount || 0}건, ${this.formatAmount(s.totalAmount)}`,
                segClass:     'pl-funnel__seg' + (isEmpty ? ' pl-funnel__seg--empty' : ''),
                segStyle:     `width: ${finalPct.toFixed(2)}%; background: ${color};`,
                cardClass:    'pl-stages__item' + (isEmpty ? ' pl-stages__item--empty' : ''),
                dotStyle:     `background: ${color};`,
                showInlineLabel: !isEmpty && finalPct >= INLINE_LABEL_THRESHOLD_PCT
            };
        });
    }

    get totalCount() {
        return (this.dashboard?.stagePipeline ?? [])
            .reduce((sum, s) => sum + (s.oppCount || 0), 0);
    }

    get totalAmountText() {
        const total = (this.dashboard?.stagePipeline ?? [])
            .reduce((sum, s) => sum + (Number(s.totalAmount) || 0), 0);
        return this.formatAmount(total);
    }

    /** ₩XX억 / ₩XX만 / ₩XX 형식 */
    formatAmount(v) {
        if (!v) return '₩0';
        const n = Number(v);
        if (n >= 100000000) return '₩' + (n / 100000000).toFixed(1) + '억';
        if (n >= 10000)     return '₩' + Math.round(n / 10000).toLocaleString('ko-KR') + '만';
        return '₩' + Math.round(n).toLocaleString('ko-KR');
    }

    /** funnel 인라인 라벨용 컴팩트 표기 (단위 살짝 짧게) */
    formatAmountShort(v) {
        if (!v) return '';
        const n = Number(v);
        if (n >= 100000000) return (n / 100000000).toFixed(1) + '억';
        if (n >= 10000)     return Math.round(n / 10000) + '만';
        return String(Math.round(n));
    }

    handleStageClick(e) {
        // standard Opportunity list — stage 필터 ListView 가 조직별로 다양해
        // 일단 AllOpportunities 로 진입 (사용자가 리스트뷰에서 stage 컬럼 정렬)
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'list'
            },
            state: { filterName: 'AllOpportunities' }
        });
    }
}
