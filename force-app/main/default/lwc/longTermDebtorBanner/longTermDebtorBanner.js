import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import LONG_TERM from '@salesforce/schema/Account.Long_Term_Debtor__c';
import TOTAL_AR from '@salesforce/schema/Account.Total_AR__c';
import CREDIT_LIMIT from '@salesforce/schema/Account.Credit_Limit__c';
import NAME from '@salesforce/schema/Account.Name';

export default class LongTermDebtorBanner extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId',
                       fields: [LONG_TERM, TOTAL_AR, CREDIT_LIMIT, NAME] })
    record;

    get isDebtor() {
        return getFieldValue(this.record.data, LONG_TERM) === true;
    }

    get accountName() {
        return getFieldValue(this.record.data, NAME);
    }

    get totalAR() {
        return this.formatKrw(getFieldValue(this.record.data, TOTAL_AR));
    }

    get creditLimit() {
        return this.formatKrw(getFieldValue(this.record.data, CREDIT_LIMIT));
    }

    get overLimit() {
        const ar = getFieldValue(this.record.data, TOTAL_AR) || 0;
        const cl = getFieldValue(this.record.data, CREDIT_LIMIT) || 0;
        return cl > 0 && ar > cl;
    }

    get exceedAmount() {
        const ar = getFieldValue(this.record.data, TOTAL_AR) || 0;
        const cl = getFieldValue(this.record.data, CREDIT_LIMIT) || 0;
        return this.formatKrw(Math.max(0, ar - cl));
    }

    formatKrw(v) {
        if (v == null) return '₩0';
        return '₩' + Number(v).toLocaleString('ko-KR');
    }
}
