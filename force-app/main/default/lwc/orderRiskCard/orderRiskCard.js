import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getRiskView from '@salesforce/apex/OrderErpSyncService.getRiskView';
import syncOrders from '@salesforce/apex/OrderErpSyncService.syncOrders';
import draftDelayNotice from '@salesforce/apex/DelayNoticeService.draft';
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';

const PRODUCTION_STATUS_LABELS = {
    Pending:    '대기',
    InProgress: '진행중',
    Done:       '완료',
    Shipped:    '출고완료'
};

export default class OrderRiskCard extends NavigationMixin(LightningElement) {
    @api recordId;

    labels = { aiLoading: AI_LOADING };

    wiredView;
    view;
    lastSignals = [];
    errorMessage = '';
    isLoading = true;
    isSyncing = false;

    @wire(getRiskView, { orderId: '$recordId' })
    handle(result) {
        this.wiredView = result;
        this.isLoading = false;
        if (result.data) {
            this.view = result.data;
            this.errorMessage = '';
        } else if (result.error) {
            this.errorMessage =
                result.error.body?.message || result.error.message || '조회 실패';
        }
    }

    // LEX 우측상단 새로고침 버튼 → wire 강제 다시 fetch
    connectedCallback() {
        this._refreshHandler = () => refreshApex(this.wiredView);
        this.template.addEventListener(RefreshEvent.TYPE, this._refreshHandler);
    }
    disconnectedCallback() {
        if (this._refreshHandler) {
            this.template.removeEventListener(RefreshEvent.TYPE, this._refreshHandler);
        }
    }

    async handleSync() {
        if (!this.recordId || this.isSyncing) return;
        this.isSyncing = true;
        this.errorMessage = '';
        try {
            const outs = await syncOrders({ orderIds: [this.recordId] });
            this.lastSignals = outs?.[0]?.signals ?? [];
            await refreshApex(this.wiredView);
            this.toast('동기화 완료',
                       `위험 점수 ${this.view?.riskScore ?? '-'}점`,
                       'success');
        } catch (e) {
            this.errorMessage = e.body?.message || e.message || '동기화 실패';
            this.toast('동기화 실패', this.errorMessage, 'error');
        } finally {
            this.isSyncing = false;
        }
    }

    async handleNotify() {
        // 78점+ 위험 Order — AI 작성 사전 통보 메일 (FR-ORDER-004, DelayNotice Prompt)
        if (!this.recordId) return;
        this.isLoading = true;
        try {
            const ctx = this.lastSignals?.length
                ? `ERP 신호: ${this.lastSignals.join(' / ')}`
                : '';
            const d = await draftDelayNotice({ orderId: this.recordId, additionalContext: ctx });
            const subject = encodeURIComponent(d.subject || '[한도정밀] 납기 지연 사전 통보');
            const body = encodeURIComponent(d.body || '본문');
            this.toast(
                d.aiSource === 'ai' ? 'AI 초안 생성' : 'Fallback 초안',
                d.aiSource === 'ai' ? '메일 클라이언트로 전달합니다' : 'AI 실패 — 기본 템플릿 사용',
                d.aiSource === 'ai' ? 'success' : 'warning'
            );
            window.open(`mailto:?subject=${subject}&body=${body}`, '_self');
        } catch (e) {
            this.toast('초안 실패', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ─────────────────────────────────────────────────────────────────────
    // getters
    // ─────────────────────────────────────────────────────────────────────

    get hasView() { return !!this.view; }

    get isSynced() { return !!this.view?.lastErpSyncAt; }
    get isUnsynced() { return !this.view?.lastErpSyncAt; }

    get score() { return this.view?.riskScore ?? null; }
    get scoreText() {
        return this.score == null ? '미동기화' : `${this.score}점`;
    }

    get riskLevel() {
        const s = this.score ?? 0;
        if (this.score == null) return 'none';
        if (s >= 70) return 'high';
        if (s >= 40) return 'mid';
        return 'low';
    }

    get riskLabel() {
        return ({ high: '위험', mid: '주의', low: '안전', none: '-' })[this.riskLevel];
    }

    get cardClass() {
        return `slds-box bl-card bl-card_${this.riskLevel}`;
    }
    get badgeClass() {
        return `bl-badge bl-badge_${this.riskLevel}`;
    }
    get scoreBarStyle() {
        return `width: ${Math.min(100, this.score ?? 0)}%;`;
    }

    get statusLabel() {
        return PRODUCTION_STATUS_LABELS[this.view?.productionStatus] || '-';
    }

    get lastSyncedDisplay() {
        if (!this.view?.lastErpSyncAt) return '아직 동기화하지 않았습니다';
        const d = new Date(this.view.lastErpSyncAt);
        return d.toLocaleString('ko-KR');
    }

    get showNotifyAction() {
        return this.score != null && this.score >= 70;
    }

    get hasEndDate() {
        return !!this.view?.endDate;
    }

    get dueBadgeClass() {
        const label = this.view?.dueLabel || '';
        if (!label) return 'slds-badge';
        if (label.indexOf('초과') >= 0) return 'slds-badge slds-theme_error slds-m-left_x-small';
        if (label.indexOf('D-day') >= 0 || label.indexOf('D-1') >= 0 ||
            label.indexOf('D-2') >= 0 || label.indexOf('D-3') >= 0) {
            return 'slds-badge slds-theme_warning slds-m-left_x-small';
        }
        return 'slds-badge slds-m-left_x-small';
    }

    get hasSignals() { return this.lastSignals.length > 0; }

    // D38 Phase 2 — ERP 예상 출고일·사유
    get hasErpForecast() {
        return !!(this.view?.expectedShipDate || this.view?.delayReason);
    }
    get hasExpectedShipDate() {
        return !!this.view?.expectedShipDate;
    }

    get syncButtonLabel() {
        return this.isSyncing ? '동기화 중...' : 'ERP 동기화';
    }
}
