import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummary from '@salesforce/apex/PaymentService.getSummary';
import register from '@salesforce/apex/PaymentService.register';

const STATUS_LABEL = {
    Pending: '대기',
    Paid: '입금완료',
    Cancelled: '취소'
};

export default class PaymentRegister extends LightningElement {
    @api recordId;

    wiredSummary;
    summary;
    errorMessage = '';
    isLoading = true;
    isSubmitting = false;

    paidDate;
    paidAmount;
    memo = '';

    @wire(getSummary, { orderId: '$recordId' })
    handle(result) {
        this.wiredSummary = result;
        this.isLoading = false;
        if (result.data) {
            this.summary = result.data;
            this.errorMessage = '';
        } else if (result.error) {
            this.errorMessage = result.error.body?.message || result.error.message || '조회 실패';
        }
    }

    handleDateChange(e)   { this.paidDate = e.target.value; }
    handleAmountChange(e) { this.paidAmount = Number(e.target.value); }
    handleMemoChange(e)   { this.memo = e.target.value; }

    async handleSubmit() {
        if (this.isSubmitting) return;
        if (!this.paidAmount || this.paidAmount <= 0) {
            this.toast('입력 오류', '입금액을 0 보다 크게 입력하세요.', 'warning');
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            const result = await register({
                orderId: this.recordId,
                paidDate: this.paidDate || this.todayIso,
                amount: this.paidAmount,
                memo: this.memo?.trim() || null
            });
            await refreshApex(this.wiredSummary);
            this.toast('입금 등록 완료',
                       `누적 ${this.formatKrw(result.totalPaid)} / 잔액 ${this.formatKrw(result.outstanding)}`,
                       'success');
            this.paidAmount = null;
            this.memo = '';
        } catch (e) {
            this.errorMessage = e.body?.message || e.message || '입금 등록 실패';
            this.toast('입금 등록 실패', this.errorMessage, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    // ─── getters ───
    get hasSummary() { return !!this.summary; }

    get totalAmount()   { return this.formatKrw(this.summary?.totalAmount); }
    get totalPaid()     { return this.formatKrw(this.summary?.totalPaid); }
    get outstanding()   { return this.formatKrw(this.summary?.outstanding); }

    get progressPct() {
        const t = this.summary?.totalAmount ?? 0;
        const p = this.summary?.totalPaid ?? 0;
        if (t <= 0) return 0;
        return Math.min(100, Math.round((p / t) * 100));
    }
    get progressStyle() { return `width: ${this.progressPct}%;`; }

    get progressLabel() { return `${this.progressPct}% 입금`; }

    get statusBadgeClass() {
        if (this.summary?.isPaidInFull) return 'bl-badge bl-badge_full';
        if (this.progressPct > 0)       return 'bl-badge bl-badge_partial';
        return 'bl-badge bl-badge_none';
    }
    get statusBadgeLabel() {
        if (this.summary?.isPaidInFull) return '완납';
        if (this.progressPct > 0)       return '부분 입금';
        return '미입금';
    }

    get hasPayments()    { return (this.summary?.payments?.length ?? 0) > 0; }
    get paymentRows() {
        return (this.summary?.payments ?? []).map(p => ({
            id: p.Id,
            paidDate: this.formatDate(p.Paid_Date__c),
            paidAmount: this.formatKrw(p.Paid_Amount__c),
            status: STATUS_LABEL[p.Status__c] || p.Status__c,
            memo: p.Memo__c || '-'
        }));
    }

    get todayIso() {
        const d = new Date();
        d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
        return d.toISOString().slice(0, 10);
    }

    formatKrw(v) {
        if (v == null) return '₩0';
        return '₩' + Number(v).toLocaleString('ko-KR');
    }
    formatDate(iso) {
        if (!iso) return '-';
        return new Date(iso).toLocaleDateString('ko-KR');
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
