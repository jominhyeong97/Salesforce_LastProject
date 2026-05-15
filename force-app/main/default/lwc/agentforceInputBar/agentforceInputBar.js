import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ask from '@salesforce/apex/AgentforceInputBarService.ask';
import AI_LOADING from '@salesforce/label/c.AI_Loading_Message';

const MSG_CAP = 50;

const ACTION_LABEL = {
    GetTodayPriorityListAction: '오늘 우선순위',
    GetOrderAtRiskAction:        '납기 위험',
    GetAccountSummaryAction:     '고객사 요약',
    GetCrossSellCandidatesAction:'교차 판매',
    DraftFollowupEmailAction:    'Follow-up 메일',
    llm_fallback:                'LLM 자유 응답',
    missing_args:                '안내',
    fallback:                    '도움말',
    error:                       '오류'
};

export default class AgentforceInputBar extends NavigationMixin(LightningElement) {
    @api recordId;
    @api hideHeader = false;   // chatbotFab embed 시 자체 헤더 숨김

    get showHeader() { return !this.hideHeader; }

    labels = { aiLoading: AI_LOADING };

    messages = [];
    utterance = '';
    isLoading = false;
    nextMsgId = 1;

    handleInput(e) {
        this.utterance = e.detail.value;
    }

    handleKey(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleAsk();
        }
    }

    async handleAsk() {
        const text = (this.utterance || '').trim();
        if (!text || this.isLoading) return;

        this.pushMessage({
            role: 'user',
            segments: [{ key: 'u-0', text, recordId: null }]
        });
        this.utterance = '';
        this.isLoading = true;

        try {
            const resp = await ask({
                utterance: text,
                contextRecordId: this.recordId || null
            });
            const segs = this.parseInlineIds(resp.message || '');
            this.pushMessage({
                role: 'ai',
                action: resp.action,
                actionLabel: ACTION_LABEL[resp.action] || resp.action,
                urgency: resp.urgency,
                segments: segs,
                isLlmFallback: resp.action === 'llm_fallback',
                isInfo: resp.action === 'missing_args' || resp.action === 'fallback',
                isError: resp.action === 'error'
            });
        } catch (e) {
            this.pushMessage({
                role: 'ai',
                action: 'error',
                actionLabel: '오류',
                segments: [{ key: 'e-0', text: e.body?.message || e.message || '알 수 없는 오류', recordId: null }],
                isError: true
            });
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    pushMessage(m) {
        m.id = this.nextMsgId++;
        m.cssClass = this.cssFor(m);
        m.avatar = m.role === 'user' ? '🙋' : '🤖';
        const arr = [...this.messages, m];
        this.messages = arr.length > MSG_CAP ? arr.slice(arr.length - MSG_CAP) : arr;
        this.scrollToBottom();
    }

    cssFor(m) {
        if (m.role === 'user') return 'msg msg-user';
        if (m.isError) return 'msg msg-ai msg-error';
        if (m.isLlmFallback) return 'msg msg-ai msg-llm';
        if (m.isInfo) return 'msg msg-ai msg-info';
        return 'msg msg-ai msg-action';
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const log = this.template.querySelector('.chatbot__log');
            if (log) log.scrollTop = log.scrollHeight;
        }, 0);
    }

    parseInlineIds(message) {
        if (!message) return [{ key: 's-0', text: '', recordId: null }];
        const re = /(\S+?)\{\{id:([a-zA-Z0-9]{15,18})\}\}/g;
        const segments = [];
        let lastIdx = 0;
        let m;
        let i = 0;
        while ((m = re.exec(message)) !== null) {
            if (m.index > lastIdx) {
                segments.push({ key: 's-' + i++, text: message.slice(lastIdx, m.index), recordId: null });
            }
            segments.push({ key: 's-' + i++, text: m[1], recordId: m[2] });
            lastIdx = re.lastIndex;
        }
        if (lastIdx < message.length) {
            segments.push({ key: 's-' + i++, text: message.slice(lastIdx), recordId: null });
        }
        return segments.length === 0
            ? [{ key: 's-0', text: message, recordId: null }]
            : segments;
    }

    handleNav(e) {
        e.preventDefault();
        const id = e.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' }
        });
    }

    get hasMessages() {
        return this.messages.length > 0;
    }
}
