import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import markShipped from '@salesforce/apex/ShippingCompleteService.markShipped';

import PROD_STATUS from '@salesforce/schema/Order.Production_Status__c';
import SHIPPED_DATE from '@salesforce/schema/Order.Shipped_Date__c';
import ORDER_NAME from '@salesforce/schema/Order.Name';

const STATUS_LABEL = {
    Pending: '대기',
    InProgress: '진행중',
    Done: '완료',
    Shipped: '출고완료'
};

export default class ShippingComplete extends LightningElement {
    @api recordId;

    wiredOrder;
    selectedDate;
    note = '';
    isSubmitting = false;
    errorMessage = '';

    @wire(getRecord, { recordId: '$recordId', fields: [PROD_STATUS, SHIPPED_DATE, ORDER_NAME] })
    handle(result) {
        this.wiredOrder = result;
        if (result.error) {
            this.errorMessage = result.error.body?.message || '조회 실패';
        }
    }

    get orderName()       { return getFieldValue(this.wiredOrder?.data, ORDER_NAME); }
    get productionStatus(){ return getFieldValue(this.wiredOrder?.data, PROD_STATUS); }
    get shippedDate()     { return getFieldValue(this.wiredOrder?.data, SHIPPED_DATE); }

    get statusLabel()       { return STATUS_LABEL[this.productionStatus] || '-'; }
    get isDone()            { return this.productionStatus === 'Done'; }
    get isShipped()         { return this.productionStatus === 'Shipped'; }
    get isNotReady()        { return !this.isDone && !this.isShipped; }

    get cardClass() {
        if (this.isShipped) return 'slds-box bl-card bl-card_done';
        if (this.isDone)    return 'slds-box bl-card bl-card_ready';
        return 'slds-box bl-card bl-card_wait';
    }

    get shippedDateDisplay() {
        if (!this.shippedDate) return '-';
        return new Date(this.shippedDate).toLocaleDateString('ko-KR');
    }

    get todayIso() {
        const d = new Date();
        d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
        return d.toISOString().slice(0, 10);
    }

    handleDateChange(e)  { this.selectedDate = e.target.value; }
    handleNoteChange(e)  { this.note = e.target.value; }

    async handleSubmit() {
        if (!this.isDone || this.isSubmitting) return;
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            const result = await markShipped({
                orderId: this.recordId,
                shippedDate: this.selectedDate || this.todayIso,
                note: this.note?.trim() || null
            });
            await refreshApex(this.wiredOrder);
            this.toast('출고 등록 완료',
                       `${result.orderName || ''} → 출고일 ${this.formatDate(result.shippedDate)}`,
                       'success');
            this.note = '';
        } catch (e) {
            this.errorMessage = e.body?.message || e.message || '출고 등록 실패';
            this.toast('출고 등록 실패', this.errorMessage, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    formatDate(iso) {
        if (!iso) return '-';
        return new Date(iso).toLocaleDateString('ko-KR');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
