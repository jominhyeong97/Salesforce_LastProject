import { LightningElement, api } from 'lwc';

export default class QuoteLineEditor extends LightningElement {
    @api line;

    qty       = 0;
    price     = 0;
    discount  = 0;
    isModified = false;

    connectedCallback() {
        this.resetFromLine();
    }

    @api
    resetFromLine() {
        this.qty      = this.line?.quantity ?? 0;
        this.price    = this.line?.unitPrice ?? 0;
        this.discount = this.line?.discountAmount ?? 0;
        this.isModified = false;
    }

    handleQtyChange(e)      { this.qty      = this.toNum(e.target.value); this.isModified = true; }
    handlePriceChange(e)    { this.price    = this.toNum(e.target.value); this.isModified = true; }
    handleDiscountChange(e) { this.discount = this.toNum(e.target.value); this.isModified = true; }

    toNum(v) {
        if (v === null || v === undefined || v === '') return 0;
        const n = Number(v);
        return Number.isFinite(n) ? n : 0;
    }

    handleSave() {
        this.dispatchEvent(new CustomEvent('linesave', {
            detail: {
                qliId: this.line.id,
                quantity: this.qty,
                unitPrice: this.price,
                discountAmount: this.discount
            }
        }));
    }

    handleDelete() {
        this.dispatchEvent(new CustomEvent('linedelete', {
            detail: { qliId: this.line.id }
        }));
    }

    handleCancel() {
        this.resetFromLine();
    }

    get rowClass() {
        return this.isModified ? 'bl-row bl-row_modified' : 'bl-row';
    }

    get previewSubtotal() {
        return (this.qty || 0) * (this.price || 0);
    }
    get previewNet() {
        return this.previewSubtotal - (this.discount || 0);
    }
    get previewDiscountPercent() {
        if (!this.previewSubtotal) return '0.00';
        return ((this.discount || 0) / this.previewSubtotal * 100).toFixed(2);
    }
}
