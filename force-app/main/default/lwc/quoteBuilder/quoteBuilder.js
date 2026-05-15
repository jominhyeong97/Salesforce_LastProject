import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getQuoteSummary from '@salesforce/apex/PricingService.getQuoteSummary';
import getActiveProducts from '@salesforce/apex/PricingService.getActiveProducts';
import updateLine from '@salesforce/apex/PricingService.updateLine';
import addLineApex from '@salesforce/apex/PricingService.addLine';
import deleteLineApex from '@salesforce/apex/PricingService.deleteLine';
import generatePdf from '@salesforce/apex/QuotePdfService.generatePdf';
import getLatestPdfId from '@salesforce/apex/QuotePdfService.getLatestPdfId';
import sendQuote from '@salesforce/apex/QuoteEmailService.sendQuote';
import getDefaultEmail from '@salesforce/apex/QuoteEmailService.getDefaultEmail';
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';

export default class QuoteBuilder extends NavigationMixin(LightningElement) {
    labels = { aiLoading: AI_LOADING };
    @api recordId;

    wiredSummary;
    summary;
    products = [];

    showAddModal = false;
    selectedProductId = null;
    addQuantity = 1;

    showEmailModal = false;
    toEmail = '';
    emailSubject = '';
    emailBody = '';
    pdfContentDocumentId = null;

    isLoading = false;

    @wire(getQuoteSummary, { quoteId: '$recordId' })
    handleSummary(result) {
        this.wiredSummary = result;
        if (result.data) {
            this.summary = result.data;
        }
    }

    @wire(getActiveProducts, { quoteId: '$recordId' })
    handleProducts({ data }) {
        if (data) this.products = data;
    }

    wiredLatestPdf;
    @wire(getLatestPdfId, { quoteId: '$recordId' })
    handleLatestPdf(result) {
        this.wiredLatestPdf = result;
        if (result.data) {
            this.pdfContentDocumentId = result.data;
        }
    }

    get hasSummary() { return !!this.summary; }
    get header()    { return this.summary?.header; }
    get lines()     { return this.summary?.lines ?? []; }
    get totals()    { return this.summary?.summary; }
    get hasLines()  { return this.lines.length > 0; }

    // FR-AR-003 — AR 헤더 노출 조건: Account 에 미수금/한도/장기미수 중 하나라도 있을 때
    get showArHeader() {
        const h = this.header;
        if (!h) return false;
        return (h.totalAR && h.totalAR > 0) || h.creditLimit || h.longTermDebtor;
    }

    get productOptions() {
        return this.products.map(p => ({
            label: `${p.productName} (${p.productCode})`,
            value: p.productId
        }));
    }

    get pdfDisabled() {
        return !this.pdfContentDocumentId;
    }

    handleProductSelect(event) { this.selectedProductId = event.detail.value; }
    handleAddQtyChange(event)  { this.addQuantity = Number(event.detail.value) || 1; }

    openAddModal() {
        this.showAddModal = true;
        this.selectedProductId = null;
        this.addQuantity = 1;
    }
    closeAddModal() {
        this.showAddModal = false;
    }

    async handleAddLine() {
        if (!this.selectedProductId) {
            this.toast('Product 선택', '추가할 제품을 선택하세요', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await addLineApex({
                quoteId: this.recordId,
                productId: this.selectedProductId,
                quantity: this.addQuantity
            });
            await refreshApex(this.wiredSummary);
            this.closeAddModal();
            this.toast('추가됨', '라인이 추가되었습니다', 'success');
        } catch (e) {
            this.toast('실패', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleLineSave(event) {
        const { qliId, quantity, unitPrice, discountAmount } = event.detail;
        this.isLoading = true;
        try {
            await updateLine({ qliId, quantity, unitPrice, discountAmount });
            await refreshApex(this.wiredSummary);
            this.toast('저장됨', '라인이 업데이트되었습니다', 'success');
        } catch (e) {
            this.toast('실패', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleLineDelete(event) {
        const { qliId } = event.detail;
        this.isLoading = true;
        try {
            await deleteLineApex({ qliId });
            await refreshApex(this.wiredSummary);
            this.toast('삭제됨', '라인이 삭제되었습니다', 'success');
        } catch (e) {
            this.toast('실패', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        refreshApex(this.wiredSummary);
    }

    async handleGeneratePdf() {
        this.isLoading = true;
        try {
            const cdId = await generatePdf({ quoteId: this.recordId });
            this.pdfContentDocumentId = cdId;
            if (this.wiredLatestPdf) await refreshApex(this.wiredLatestPdf);
            this.toast('PDF 생성됨', 'Quote에 견적서가 첨부되었습니다', 'success');
        } catch (e) {
            this.toast('PDF 생성 실패', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePreviewPdf() {
        if (!this.pdfContentDocumentId) {
            this.toast('PDF 없음', '먼저 [PDF 생성] 버튼을 누르세요', 'warning');
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: this.pdfContentDocumentId }
        });
    }

    async openEmailModal() {
        if (!this.pdfContentDocumentId) {
            this.toast('PDF 없음', '먼저 [PDF 생성] 버튼으로 견적서를 첨부하세요', 'warning');
            return;
        }
        this.showEmailModal = true;
        this.toEmail = '';
        try {
            const def = await getDefaultEmail({ quoteId: this.recordId });
            this.emailSubject = def?.subject || '';
            this.emailBody    = def?.body || '';
        } catch (e) {
            this.emailSubject = '';
            this.emailBody = '';
        }
    }
    closeEmailModal() {
        this.showEmailModal = false;
    }
    handleEmailChange(event)   { this.toEmail = event.detail.value; }
    handleSubjectChange(event) { this.emailSubject = event.detail.value; }
    handleBodyChange(event)    { this.emailBody = event.target.value; }

    async handleSendEmail() {
        if (!this.toEmail || !this.toEmail.includes('@')) {
            this.toast('이메일 주소', '올바른 이메일 주소를 입력하세요', 'warning');
            return;
        }
        if (!this.emailSubject?.trim()) {
            this.toast('제목', '이메일 제목을 입력하세요', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            await sendQuote({
                quoteId: this.recordId,
                toEmail: this.toEmail,
                contentDocumentId: this.pdfContentDocumentId,
                subject: this.emailSubject,
                body: this.emailBody
            });
            await refreshApex(this.wiredSummary);
            this.closeEmailModal();
            this.toast('발송 완료', '견적서를 이메일로 발송했습니다', 'success');
        } catch (e) {
            this.toast('발송 실패', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
