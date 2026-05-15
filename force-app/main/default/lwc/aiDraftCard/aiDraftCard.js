import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateAiQuote from '@salesforce/apex/AiQuoteDraftService.generateAiQuote';

export default class AiDraftCard extends NavigationMixin(LightningElement) {
    @api recordId;

    isLoading = false;
    result = null;
    errorMessage = '';

    get hasResult()    { return !!this.result; }
    get hasError()     { return !!this.errorMessage; }
    get showInitial()  { return !this.isLoading && !this.hasResult && !this.hasError; }
    get confidencePct() {
        if (!this.result?.confidence) return '0%';
        return (this.result.confidence * 100).toFixed(0) + '%';
    }
    get confidenceClass() {
        const c = this.result?.confidence ?? 0;
        if (c >= 0.8) return 'bl-conf bl-conf_high';
        if (c >= 0.5) return 'bl-conf bl-conf_mid';
        return 'bl-conf bl-conf_low';
    }

    async handleGenerate() {
        this.isLoading = true;
        this.errorMessage = '';
        this.result = null;
        try {
            const r = await generateAiQuote({ opportunityId: this.recordId });
            this.result = r;
            this.dispatchEvent(new ShowToastEvent({
                title: 'AI 견적 초안 생성 완료',
                message: r.quoteName + ' 생성됨 — Quote 페이지로 이동합니다',
                variant: 'success'
            }));
        } catch (e) {
            this.errorMessage = e.body?.message || e.message || '알 수 없는 오류';
        } finally {
            this.isLoading = false;
        }
    }

    handleNavigate() {
        if (!this.result?.quoteId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.result.quoteId,
                objectApiName: 'Quote',
                actionName: 'view'
            }
        });
    }

    handleReset() {
        this.result = null;
        this.errorMessage = '';
    }
}
