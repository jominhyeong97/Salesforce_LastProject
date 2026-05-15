import { LightningElement, api } from 'lwc';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import processLicense from '@salesforce/apex/BusinessLicensePromptService.processLicense';
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';

const STATUS = Object.freeze({
    SUCCESS:        'success',
    PARTIAL:        'partial',
    EXTRACT_EMPTY:  'extract_empty',
    ERROR_OCR:      'error_ocr',
    ERROR_ACCOUNT:  'error_account',
    ERROR_FILE:     'error_file'
});

const MAX_FILE_SIZE = 5 * 1024 * 1024;
const ALLOWED_EXT   = ['jpg', 'jpeg', 'png'];
const FIELD_LABELS = {
    businessNumber: '사업자등록번호',
    companyName:    '상호',
    ceoName:        '대표자',
    address:        '사업장 소재지'
};

export default class BusinessLicenseUpload extends LightningElement {
    @api recordId;

    labels = { aiLoading: AI_LOADING };

    isLoading    = false;
    isDragOver   = false;
    result       = null;
    errorMessage = '';

    get isSuccess()      { return this.result?.status === STATUS.SUCCESS; }
    get isPartial()      { return this.result?.status === STATUS.PARTIAL; }
    get isExtractEmpty() { return this.result?.status === STATUS.EXTRACT_EMPTY; }
    get isError() {
        const s = this.result?.status;
        return s === STATUS.ERROR_OCR || s === STATUS.ERROR_ACCOUNT || s === STATUS.ERROR_FILE;
    }
    get showUploadForm() {
        return !this.isLoading && (!this.result || this.isError || this.isExtractEmpty);
    }
    get dragOverClass() {
        return this.isDragOver
            ? 'slds-file-selector__dropzone slds-has-drag-over'
            : 'slds-file-selector__dropzone';
    }

    get enrichedList() {
        return (this.result?.enrichedFields ?? []).map(k => ({
            key: k,
            label: FIELD_LABELS[k] ?? k
        }));
    }
    get partialList() {
        return (this.result?.partialFailures ?? []).map(k => ({
            key: k,
            label: FIELD_LABELS[k] ?? k
        }));
    }
    get hasPartialList() { return (this.result?.partialFailures?.length ?? 0) > 0; }

    handleFileSelect(event) {
        const file = event.target.files?.[0];
        if (file) this.processFile(file);
        event.target.value = '';
    }
    handleDragOver(event)  { event.preventDefault(); this.isDragOver = true; }
    handleDragLeave(event) { event.preventDefault(); this.isDragOver = false; }
    handleFileDrop(event) {
        event.preventDefault();
        this.isDragOver = false;
        const file = event.dataTransfer?.files?.[0];
        if (file) this.processFile(file);
    }

    processFile(file) {
        if (!this.validateFile(file)) return;

        this.isLoading    = true;
        this.errorMessage = '';
        this.result       = null;

        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            this.callApex(file.name, base64);
        };
        reader.onerror = () => {
            this.isLoading = false;
            this.errorMessage = '파일 읽기 실패. 다시 시도하세요.';
        };
        reader.readAsDataURL(file);
    }

    validateFile(file) {
        if (file.size > MAX_FILE_SIZE) {
            this.errorMessage = `파일 크기는 5MB 이하여야 합니다. (현재: ${(file.size / 1024 / 1024).toFixed(2)}MB)`;
            return false;
        }
        const ext = file.name.split('.').pop().toLowerCase();
        if (!ALLOWED_EXT.includes(ext)) {
            this.errorMessage = `파일 형식은 jpg, jpeg, png만 가능합니다. (현재: .${ext})`;
            return false;
        }
        return true;
    }

    async callApex(fileName, base64) {
        try {
            const result = await processLicense({
                opportunityId: this.recordId,
                fileName,
                base64FileContent: base64
            });
            this.result = result;
            this.errorMessage = result.errorMessage || '';

            if (this.isSuccess || this.isPartial) {
                getRecordNotifyChange([{ recordId: this.recordId }]);
                this.dispatchEvent(new RefreshEvent());
                try {
                    // eslint-disable-next-line no-eval
                    eval("$A.get('e.force:refreshView').fire();");
                } catch (e) {
                    // Aura 호스트 외부에서는 무음 fallback
                }
                this.dispatchEvent(new CustomEvent('license_enriched', {
                    detail: {
                        enrichedFields: result.enrichedFields,
                        extracted:      result.extracted
                    }
                }));
            }
        } catch (error) {
            this.result = {
                status:          STATUS.ERROR_OCR,
                enrichedFields:  [],
                partialFailures: []
            };
            this.errorMessage = `Apex 호출 실패: ${error.body?.message || error.message}`;
        } finally {
            this.isLoading = false;
        }
    }

    handleRetry() {
        this.result = null;
        this.errorMessage = '';
    }
}
