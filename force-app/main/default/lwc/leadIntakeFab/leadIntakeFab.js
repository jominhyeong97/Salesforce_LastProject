import { LightningElement } from 'lwc';

export default class LeadIntakeFab extends LightningElement {
    isOpen = false;

    handleToggle() {
        this.isOpen = !this.isOpen;
    }

    handleClose() {
        this.isOpen = false;
    }

    get fabIcon() {
        return this.isOpen ? '✕' : '📞';
    }

    get fabClass() {
        return this.isOpen ? 'fab fab--open' : 'fab';
    }
}
