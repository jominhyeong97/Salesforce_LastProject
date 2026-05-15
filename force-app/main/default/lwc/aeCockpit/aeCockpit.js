import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { RefreshEvent } from 'lightning/refresh';
import load from '@salesforce/apex/AeCockpitService.load';

const CHANNEL_LABEL = {
    EMAIL: '이메일',
    PHONE: '전화',
    VISIT: '방문',
    WEB:   '웹'
};

const PROD_STATUS_LABEL = {
    Pending:    '대기',
    InProgress: '진행중',
    Done:       '완료',
    Shipped:    '출고완료'
};

export default class AeCockpit extends NavigationMixin(LightningElement) {

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
            this.errorMessage = result.error.body?.message || result.error.message || '조회 실패';
        }
    }

    // LEX 우측상단 새로고침 버튼 → wire 강제 다시 fetch
    connectedCallback() {
        this._refreshHandler = () => refreshApex(this.wiredResult);
        this.template.addEventListener(RefreshEvent.TYPE, this._refreshHandler);
    }
    disconnectedCallback() {
        if (this._refreshHandler) {
            this.template.removeEventListener(RefreshEvent.TYPE, this._refreshHandler);
        }
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredResult).finally(() => { this.isLoading = false; });
    }

    navigateTo(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    handleLeadClick(e)    { this.navigateTo(e.currentTarget.dataset.id, 'Lead'); }
    handleQuoteClick(e)   { this.navigateTo(e.currentTarget.dataset.id, 'Quote'); }
    handleOrderClick(e)   { this.navigateTo(e.currentTarget.dataset.id, 'Order'); }
    handleAccountClick(e) { this.navigateTo(e.currentTarget.dataset.id, 'Account'); }

    // ─── transforms ───

    get hasData() { return !!this.dashboard; }

    get rfqRows() {
        return (this.dashboard?.newRfqs ?? []).map(r => ({
            ...r,
            channelLabel: CHANNEL_LABEL[r.sourceChannel] || r.sourceChannel || '-',
            createdAtText: this.formatRel(r.createdDate)
        }));
    }

    get priorityLeadRows() {
        return (this.dashboard?.priorityLeads ?? []).map(r => ({
            ...r,
            channelLabel: CHANNEL_LABEL[r.sourceChannel] || r.sourceChannel || '-',
            scoreClass: this.scoreClass(r.leadScore)
        }));
    }

    get sentQuoteRows() {
        return (this.dashboard?.sentQuotes ?? []).map(r => ({
            ...r,
            sentText:    this.formatDate(r.sentDate),
            openedLabel: r.opened ? '✅ 열람' : '⏳ 미열람',
            openedClass: r.opened ? 'bl-pill bl-pill_ok' : 'bl-pill bl-pill_warn'
        }));
    }

    get riskyOrderRows() {
        return (this.dashboard?.riskyOrders ?? []).map(r => ({
            ...r,
            statusLabel: PROD_STATUS_LABEL[r.productionStatus] || r.productionStatus || '-',
            scoreClass:  r.riskScore >= 85 ? 'bl-score bl-score_critical' : 'bl-score bl-score_high',
            dueClass:    this.dueClass(r.dueLabel)
        }));
    }

    dueClass(label) {
        if (!label) return 'bl-due';
        if (label.indexOf('초과') >= 0) return 'bl-due bl-due_overdue';
        if (label.indexOf('D-day') >= 0 || label.indexOf('D-1') >= 0 ||
            label.indexOf('D-2') >= 0 || label.indexOf('D-3') >= 0) {
            return 'bl-due bl-due_imminent';
        }
        return 'bl-due';
    }

    get arRows() {
        return (this.dashboard?.arActions ?? []).map(r => ({
            ...r,
            totalARText: this.formatKrw(r.totalAR),
            longTermBadge: r.isLongTerm ? '🚨 장기' : ''
        }));
    }

    get leadStatusBreakdown() {
        const map = {};
        (this.dashboard?.priorityLeads ?? []).forEach(l => {
            const key = l.status || '기타';
            map[key] = (map[key] || 0) + 1;
        });
        return Object.keys(map).map(s => ({
            key: s, label: s, count: map[s]
        }));
    }
    get hasLeadStatusBreakdown() {
        return this.leadStatusBreakdown.length > 0;
    }

    get hasRfqs()           { return this.rfqRows.length > 0; }
    get hasPriorityLeads()  { return this.priorityLeadRows.length > 0; }
    get hasSentQuotes()     { return this.sentQuoteRows.length > 0; }
    get hasRiskyOrders()    { return this.riskyOrderRows.length > 0; }
    get hasArActions()      { return this.arRows.length > 0; }

    scoreClass(score) {
        if (score >= 80) return 'bl-score bl-score_high';
        if (score >= 60) return 'bl-score bl-score_mid';
        return 'bl-score bl-score_low';
    }

    formatKrw(v) {
        if (v == null) return '₩0';
        return '₩' + Number(v).toLocaleString('ko-KR');
    }
    formatDate(iso) {
        if (!iso) return '-';
        return new Date(iso).toLocaleDateString('ko-KR');
    }
    formatRel(iso) {
        if (!iso) return '-';
        const ms = Date.now() - new Date(iso).getTime();
        const hr = Math.floor(ms / 3600000);
        if (hr < 1)  return '방금 전';
        if (hr < 24) return `${hr}시간 전`;
        return `${Math.floor(hr / 24)}일 전`;
    }
}
