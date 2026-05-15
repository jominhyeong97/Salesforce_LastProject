import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { createRecord } from 'lightning/uiRecordApi';
import extractMemo from '@salesforce/apex/CallMemoExtractService.extract';
import calculateScore from '@salesforce/apex/LeadScoringService.calculateScore';

const FIELD_KEYS = ['company', 'contactName', 'contactTitle', 'phone', 'partName', 'quantity', 'requestedDate'];
const EMPTY_FORM = { company: '', contactName: '', contactTitle: '', phone: '', partName: '', quantity: '', requestedDate: '' };
const CHANNEL = 'VISIT';

export default class VisitLeadIntake extends NavigationMixin(LightningElement) {
    memo = '';
    form = { ...EMPTY_FORM };
    extractedFlags = {};
    extracting = false;
    saving = false;
    extractError = '';
    saveError = '';
    lastLeadId;
    lastLeadScore;

    handleMemoChange(e) {
        this.memo = e.detail.value;
    }

    handleFieldChange(e) {
        const key = e.target.dataset.field;
        this.form = { ...this.form, [key]: e.detail.value };
        if (this.extractedFlags[key]) {
            this.extractedFlags = { ...this.extractedFlags, [key]: false };
        }
    }

    async handleExtract() {
        if (!this.memo) {
            this.extractError = '방문 노트를 입력하세요.';
            return;
        }
        this.extracting = true;
        this.extractError = '';
        try {
            const result = await extractMemo({ memo: this.memo });
            const nextForm = { ...this.form };
            const nextFlags = {};
            FIELD_KEYS.forEach(k => {
                if (result[k]) {
                    nextForm[k] = result[k];
                    nextFlags[k] = true;
                }
            });
            this.form = nextForm;
            this.extractedFlags = nextFlags;
        } catch (err) {
            this.extractError = '추출 실패: ' + this.errMsg(err);
        } finally {
            this.extracting = false;
        }
    }

    handleReset() {
        this.memo = '';
        this.form = { ...EMPTY_FORM };
        this.extractedFlags = {};
        this.extractError = '';
        this.saveError = '';
        this.lastLeadId = null;
        this.lastLeadScore = null;
    }

    async handleSave() {
        if (!this.form.company || !this.form.contactName) {
            this.saveError = '회사명과 담당자는 필수입니다.';
            return;
        }
        this.saving = true;
        this.saveError = '';
        this.lastLeadId = null;
        try {
            const spec = {
                partName: this.form.partName,
                quantity: this.form.quantity ? parseInt(this.form.quantity, 10) : null,
                requestedDate: this.form.requestedDate
            };
            const fields = {
                Company: this.form.company,
                LastName: this.form.contactName,
                Title: this.form.contactTitle,
                Phone: this.form.phone,
                Source_Channel__c: CHANNEL,
                Status: '신규',
                RFQ_Spec_JSON__c: JSON.stringify(spec),
                Description: this.memo
            };
            const record = await createRecord({ apiName: 'Lead', fields });
            const score = await calculateScore({
                lead: {
                    Source_Channel__c: CHANNEL,
                    Company: this.form.company,
                    RFQ_Spec_JSON__c: JSON.stringify(spec)
                }
            });
            this.lastLeadId = record.id;
            this.lastLeadScore = score;
        } catch (err) {
            this.saveError = '저장 실패: ' + this.errMsg(err);
        } finally {
            this.saving = false;
        }
    }

    handleOpenLead() {
        if (!this.lastLeadId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.lastLeadId,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        });
    }

    get scoreTier() {
        if (this.lastLeadScore == null) return '';
        if (this.lastLeadScore >= 70) return 'Hot';
        if (this.lastLeadScore >= 40) return 'Warm';
        return 'Cold';
    }

    get companyClass() { return this.classFor('company'); }
    get contactClass() { return this.classFor('contactName'); }
    get titleClass() { return this.classFor('contactTitle'); }
    get phoneClass() { return this.classFor('phone'); }
    get partClass() { return this.classFor('partName'); }
    get qtyClass() { return this.classFor('quantity'); }
    get dateClass() { return this.classFor('requestedDate'); }

    classFor(key) {
        return 'slds-m-bottom_x-small' + (this.extractedFlags[key] ? ' field-extracted' : '');
    }

    errMsg(err) {
        if (!err) return 'unknown';
        if (err.body?.message) return err.body.message;
        if (err.body?.output?.errors?.[0]?.message) return err.body.output.errors[0].message;
        return err.message || JSON.stringify(err);
    }
}
