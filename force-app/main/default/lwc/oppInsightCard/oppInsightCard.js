import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import analyze from '@salesforce/apex/OppInsightService.analyze';
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';

export default class OppInsightCard extends LightningElement {
    @api recordId;

    labels = { aiLoading: AI_LOADING };

    wiredInsight;
    insight;
    errorMessage = '';
    isLoading = true;

    @wire(analyze, { opportunityId: '$recordId' })
    handle(result) {
        this.wiredInsight = result;
        this.isLoading = false;
        if (result.data) {
            this.insight = result.data;
            this.errorMessage = '';
        } else if (result.error) {
            this.errorMessage = result.error.body?.message || result.error.message || '분석 실패';
        }
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredInsight).finally(() => { this.isLoading = false; });
    }

    get hasInsight() { return !!this.insight; }

    get scoreText() {
        return this.insight ? `${this.insight.score}점` : '-';
    }

    get scoreCardClass() {
        const s = this.insight?.score ?? 0;
        if (s >= 70) return 'bl-score-card bl-score-card_high';
        if (s >= 40) return 'bl-score-card bl-score-card_mid';
        return 'bl-score-card bl-score-card_low';
    }

    get scoreBarStyle() {
        const s = this.insight?.score ?? 0;
        return `width: ${s}%;`;
    }

    get aiBadgeLabel() {
        return this.insight?.aiSource === 'ai' ? 'AI 자연어 요약' : 'Fallback 요약';
    }
    get aiBadgeClass() {
        return this.insight?.aiSource === 'ai'
            ? 'bl-badge bl-badge_ai'
            : 'bl-badge bl-badge_fallback';
    }

    get hasRisks() { return (this.insight?.risks?.length ?? 0) > 0; }
    get hasNextActions() { return (this.insight?.nextActions?.length ?? 0) > 0; }

    get scoreBreakdown() {
        if (!this.insight) return [];
        return [
            { key: 'stage',      label: '단계',     value: this.insight.stageScore,      max: 50 },
            { key: 'activity',   label: '활동',     value: this.insight.activityScore,   max: 20 },
            { key: 'account',   label: 'Account',  value: this.insight.accountScore,    max: 15 },
            { key: 'engagement', label: 'Engagement', value: this.insight.engagementScore, max: 15 }
        ];
    }
}
