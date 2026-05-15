import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import SCORE_FIELD   from '@salesforce/schema/Lead.Lead_Score__c';
import CHANNEL_FIELD from '@salesforce/schema/Lead.Source_Channel__c';
import STATUS_FIELD  from '@salesforce/schema/Lead.Status';
import COMPANY_FIELD from '@salesforce/schema/Lead.Company';

const CHANNEL_LABEL = {
    PHONE: '전화',
    EMAIL: '이메일',
    VISIT: '방문',
    WEB:   '웹'
};

export default class LeadScoreBadge extends LightningElement {
    @api recordId;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [SCORE_FIELD, CHANNEL_FIELD, STATUS_FIELD, COMPANY_FIELD]
    })
    record;

    get score() {
        const v = getFieldValue(this.record?.data, SCORE_FIELD);
        return v == null ? null : Number(v);
    }

    get hasScore() {
        return this.score != null;
    }

    get scoreText() {
        return this.hasScore ? this.score + '점' : '미산정';
    }

    get level() {
        const s = this.score ?? 0;
        if (this.score == null) return 'none';
        if (s >= 80) return 'hot';
        if (s >= 60) return 'warm';
        if (s >= 40) return 'lukewarm';
        return 'cold';
    }

    get levelLabel() {
        return ({
            hot:      '핫 (Hot)',
            warm:     '웜 (Warm)',
            lukewarm: '미지근 (Lukewarm)',
            cold:     '콜드 (Cold)',
            none:     '미산정'
        })[this.level];
    }

    get stripClass() {
        return `score-strip score-strip_${this.level}`;
    }

    get barClass() {
        return `score-bar score-bar_${this.level}`;
    }

    get progressStyle() {
        const pct = this.score == null ? 0 : Math.min(100, this.score);
        return `width: ${pct}%;`;
    }

    get channelLabel() {
        const ch = getFieldValue(this.record?.data, CHANNEL_FIELD);
        return CHANNEL_LABEL[ch] || ch || '미지정';
    }

    get statusLabel() {
        return getFieldValue(this.record?.data, STATUS_FIELD) || '-';
    }

    get companyLabel() {
        return getFieldValue(this.record?.data, COMPANY_FIELD) || '';
    }

    get scoreHint() {
        if (this.score == null) return 'Lead 인입 채널·수량·사양·과거 거래 기반 자동 산출 대기';
        const s = this.score;
        if (s >= 80) return '즉시 연락 권장 — 전환 가능성 매우 높음';
        if (s >= 60) return '우선 처리 — 적극적 영업 권장';
        if (s >= 40) return '관심 단계 — 자료 발송 후 후속';
        return '저우선 — 자동 응대 또는 후순위';
    }
}
