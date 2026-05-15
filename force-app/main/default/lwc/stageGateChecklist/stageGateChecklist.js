import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import checkOppGate from '@salesforce/apex/StageGateService.checkOppGate';

export default class StageGateChecklist extends LightningElement {
    @api recordId;
    wiredResult;
    result;
    errorMessage = '';
    loading = false;

    @wire(checkOppGate, { opportunityId: '$recordId' })
    wiredCheck(value) {
        this.wiredResult = value;
        const { data, error } = value;
        if (data) {
            this.result = this.decorate(data);
            this.errorMessage = '';
        } else if (error) {
            this.errorMessage = '게이트 조회 실패: ' + (error.body?.message || error.message);
            this.result = null;
        }
    }

    decorate(data) {
        const rules = (data.rules || []).map(r => ({
            ...r,
            iconName: r.satisfied ? 'utility:success' : 'utility:close',
            iconVariant: r.satisfied ? 'success' : 'error',
            showHint: !r.satisfied
        }));
        return { ...data, rules };
    }

    get hasResult() { return !!this.result; }
    get hasRules() { return this.result && this.result.rules && this.result.rules.length > 0; }
    get nextBadgeVariant() { return this.result?.passed ? 'success' : 'inverse'; }
    get isPreWonStage() {
        return this.result?.currentStage === '협상' && this.result?.nextStage === '수주';
    }
    get isTerminalStage() {
        return this.result && this.result.currentStage === this.result.nextStage;
    }

    async handleRefresh() {
        await refreshApex(this.wiredResult);
    }
}
