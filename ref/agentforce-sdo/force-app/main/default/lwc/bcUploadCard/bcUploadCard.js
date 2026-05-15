/**
 * @fileoverview bcUploadCard — 명함 이미지 업로드 + 비동기 AI 분석 + Lead 자동 생성 LWC.
 *
 * <h3>아키텍처</h3>
 * <ul>
 *   <li>클라이언트 측에서 이미지 전처리 (resize 1600px, sharpen, JPEG 0.9)</li>
 *   <li>Apex `enqueueProcessing`으로 base64 전송 → 서버는 즉시 BusinessCard__c(Status=Queued) 반환</li>
 *   <li>3초 간격 폴링으로 `fetchResult` 호출하여 'LeadCreated' / 'Failed'까지 대기</li>
 *   <li>Job queue 패턴: 사용자가 여러 장을 연속 업로드해도 각 작업이 독립적으로 진행</li>
 * </ul>
 *
 * @see AutoLeadByBC_Service (Apex)
 */
import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import enqueueProcessing from '@salesforce/apex/AutoLeadByBC_Service.enqueueProcessing';
import fetchResult from '@salesforce/apex/AutoLeadByBC_Service.fetchResult';

/** @description 전처리 시 이미지 최대 변길이 (px). 명함 OCR에 충분하면서 페이로드 절약. */
const MAX_DIMENSION = 1600;
/** @description Unsharp masking 강도 (0~1). 0.35는 부드러운 sharpening. */
const SHARPEN_MIX = 0.35;
/** @description JPEG 인코딩 품질 (0~1). */
const JPEG_QUALITY = 0.9;
/** @description 결과 폴링 주기 (ms). */
const POLL_INTERVAL_MS = 3000;
/** @description 결과 폴링 최대 시도 — 3s × 100 = 5분 타임아웃. */
const POLL_MAX_ATTEMPTS = 100;
/** @description 단일 파일 업로드 상한 (15MB). */
const MAX_FILE_BYTES = 15 * 1024 * 1024;
/** @description 결과 도착 전 진행률 상한 (%). 100%는 결과 마감 시에만 표시. */
const PROGRESS_CAP = 92;

/** @description 진행률 단계별 상수. UI 진행 바 점프를 자연스럽게 보이도록 구분. */
const STAGE = Object.freeze({
    PREPROCESS_START: 5,
    PREPROCESS_DONE: 20,
    ENQUEUED: 35,
    POLL_FIRST: 55,
    POLL_STEP: 5,
    DONE: 100
});

/**
 * @description 명함 업로드 LWC. AppPage / HomePage / RecordPage에 배치 가능.
 * @extends LightningElement
 */
export default class BcUploadCard extends NavigationMixin(LightningElement) {
    /** @description 진행 중 + 완료된 모든 업로드 작업. 최신 작업이 배열의 앞쪽. */
    @track jobs = [];
    /** @description 신규 작업에 부여할 client-side ID 카운터. */
    nextJobId = 1;
    /** @description 드래그 진행 중 시각 효과를 위한 플래그. */
    isDragging = false;

    /** @description 컴포넌트 destroy 시 모든 폴링 타이머 정리. */
    disconnectedCallback() {
        this.jobs.forEach(j => this.clearJobTimer(j));
    }

    // ---------------- 상태 getter ----------------

    /** @returns {boolean} 작업이 1건 이상 있는가 */
    get hasJobs()      { return this.jobs.length > 0; }
    /** @returns {number} 진행 중 작업 수 */
    get activeCount()  { return this.jobs.filter(j => j.isActive).length; }
    /** @returns {boolean} 진행 중 작업이 있는가 */
    get hasActive()    { return this.activeCount > 0; }
    /** @returns {string} 큐 헤더에 표시할 라벨 (예: "진행 중 2건 / 전체 5건") */
    get queueLabel() {
        if (!this.hasJobs) return '';
        return this.hasActive
            ? `진행 중 ${this.activeCount}건 / 전체 ${this.jobs.length}건`
            : `완료 ${this.jobs.length}건`;
    }
    /** @returns {string} 드롭존 클래스 (drag 상태 반영) */
    get dropZoneClass() {
        return 'bc-dropzone' + (this.isDragging ? ' bc-dropzone_active' : '');
    }

    // ---------------- DOM 이벤트 핸들러 ----------------

    /** @description Drag-over: 시각 효과만 토글. */
    handleDragOver(event) {
        event.preventDefault();
        this.isDragging = true;
    }
    handleDragLeave() { this.isDragging = false; }

    /** @description Drop: 첫 번째 파일만 처리 (멀티 드롭은 의도적으로 지원하지 않음). */
    handleDrop(event) {
        event.preventDefault();
        this.isDragging = false;
        const file = event.dataTransfer?.files?.[0];
        if (file) this.startJob(file);
    }

    /** @description input[type=file] change. 같은 파일 재업로드 허용 위해 value 초기화. */
    handleFileChange(event) {
        const file = event.target.files?.[0];
        if (file) this.startJob(file);
        event.target.value = '';
    }

    /** @description "카메라 촬영" 버튼 → capture=environment 의 hidden input click. */
    handleCameraClick() {
        this.template.querySelector('input[data-id="cameraInput"]')?.click();
    }
    /** @description "앨범에서 선택" 버튼 → capture 없는 hidden input click. */
    handleAlbumClick() {
        this.template.querySelector('input[data-id="albumInput"]')?.click();
    }

    // ---------------- 작업 라이프사이클 ----------------

    /**
     * @description 단일 파일에 대한 작업 시작. 검증 → 전처리 → enqueue → 폴링 시작.
     * @param {File} file 업로드 대상 파일 (image/* 만 허용, 15MB 이하)
     */
    async startJob(file) {
        if (!file.type?.startsWith('image/')) {
            this.toast('이미지만 업로드할 수 있습니다', `${file.name} 은(는) 이미지 형식이 아닙니다.`, 'error');
            return;
        }
        if (file.size > MAX_FILE_BYTES) {
            this.toast('파일이 너무 큽니다', `${file.name} 은(는) 15MB를 초과했습니다.`, 'error');
            return;
        }

        const job = this.createJob(file);
        this.jobs = [job, ...this.jobs];

        try {
            this.updateJob(job.id, { progress: STAGE.PREPROCESS_START });
            const { base64, thumbnailUrl } = await this.preprocessImage(file);
            this.updateJob(job.id, { progress: STAGE.PREPROCESS_DONE, thumbnailUrl });

            const dto = await enqueueProcessing({ fileName: file.name, base64Image: base64 });
            if (dto.status === 'Failed') {
                this.markFailed(job.id, dto.failureMessage ?? '서버 거부');
                return;
            }
            this.updateJob(job.id, {
                businessCardId: dto.businessCardId,
                statusLabel: 'AI 분석 중',
                progress: STAGE.ENQUEUED
            });
            this.startPolling(job.id);
        } catch (e) {
            this.markFailed(job.id, e?.body?.message ?? e?.message ?? '업로드 실패');
        }
    }

    /**
     * @description 신규 job 객체 팩토리. UI 렌더링에 필요한 모든 필드를 미리 정의해
     *              LWC reactivity가 추후 patch로 트리거되도록 한다.
     * @param {File} file 업로드 파일
     * @returns {Object} 새 job 객체
     */
    createJob(file) {
        return {
            id: this.nextJobId++,
            fileName: file.name,
            thumbnailUrl: null,
            statusLabel: '업로드 준비 중',
            statusVariant: 'base',
            progress: 0,
            isActive: true,
            isSuccess: false,
            isFailed: false,
            businessCardId: null,
            leadId: null,
            company: null,
            lastName: null,
            title: null,
            missingFieldsLabel: null,
            duplicateCount: 0,
            errorMessage: null,
            pollTimer: null,
            pollAttempts: 0,
            startedAt: Date.now(),
            elapsedLabel: '0s',
            itemClass: 'bc-job-item bc-job-item_active'
        };
    }

    /**
     * @description 결과 폴링 타이머 시작. POLL_INTERVAL_MS 마다 fetchResult 호출.
     * @param {number} jobId
     */
    startPolling(jobId) {
        const tick = () => this.pollOnce(jobId);
        const job = this.findJob(jobId);
        if (!job) return;
        const timer = setInterval(tick, POLL_INTERVAL_MS);
        this.updateJob(jobId, { pollTimer: timer });
    }

    /**
     * @description 단일 폴링 시도. 성공/실패 시 마감, 'Queued'/'Extracting'이면 계속.
     * @param {number} jobId
     */
    async pollOnce(jobId) {
        const job = this.findJob(jobId);
        if (!job) return;

        const attempts = job.pollAttempts + 1;
        if (attempts > POLL_MAX_ATTEMPTS) {
            this.markFailed(jobId, '분석이 너무 오래 걸려 중단됐습니다. 명함 레코드에서 결과를 확인해주세요.');
            return;
        }

        // 진행률 점진 증가 (첫 폴링은 큰 점프, 이후 작은 증분)
        const nextProgress = attempts === 1
            ? STAGE.POLL_FIRST
            : Math.min(PROGRESS_CAP, job.progress + STAGE.POLL_STEP);

        this.updateJob(jobId, {
            pollAttempts: attempts,
            progress: nextProgress,
            elapsedLabel: this.formatElapsed(job.startedAt)
        });

        try {
            const dto = await fetchResult({ businessCardId: job.businessCardId });
            if (dto.status === 'LeadCreated' || dto.status === 'Mapped') {
                this.markSuccess(jobId, dto);
            } else if (dto.status === 'Failed') {
                this.markFailed(jobId, dto.failureMessage ?? '처리 실패', dto);
            }
            // 'Queued' / 'Extracting' 이면 폴링 계속
        } catch (e) {
            // 일시적 fetch 오류는 무시 — 타임아웃까지 진행
        }
    }

    /**
     * @description 작업 성공 마감. 폴링 정리 + UI 업데이트 + Toast 알림.
     * @param {number} jobId
     * @param {Object} dto AutoLeadByBC_Service.fetchResult 반환 DTO
     */
    markSuccess(jobId, dto) {
        const job = this.findJob(jobId);
        if (!job) return;
        this.clearJobTimer(job);
        this.updateJob(jobId, {
            statusLabel: '등록 완료',
            statusVariant: 'success',
            progress: STAGE.DONE,
            isActive: false,
            isSuccess: true,
            itemClass: 'bc-job-item bc-job-item_success',
            businessCardId: dto.businessCardId,
            leadId: dto.leadId,
            company: dto.company,
            lastName: dto.lastName,
            title: dto.title,
            missingFieldsLabel: (dto.missingFields ?? []).join(', ') || null,
            duplicateCount: dto.duplicateCount ?? 0,
            elapsedLabel: this.formatElapsed(job.startedAt)
        });
        this.toast('등록 완료', `${job.fileName} 처리 완료`, 'success');
    }

    /**
     * @description 작업 실패 마감. 폴링 정리 + UI 업데이트 + Toast 알림.
     * @param {number} jobId
     * @param {string} message 사용자 표시용 에러 메시지
     * @param {Object} [dto]   서버 DTO (있으면 businessCardId만 보존)
     */
    markFailed(jobId, message, dto) {
        const job = this.findJob(jobId);
        if (!job) return;
        this.clearJobTimer(job);
        this.updateJob(jobId, {
            statusLabel: '실패',
            statusVariant: 'error',
            progress: STAGE.DONE,
            isActive: false,
            isFailed: true,
            itemClass: 'bc-job-item bc-job-item_failed',
            errorMessage: message,
            businessCardId: dto?.businessCardId ?? job.businessCardId,
            elapsedLabel: this.formatElapsed(job.startedAt)
        });
        this.toast('등록 실패', `${job.fileName}: ${message}`, 'error');
    }

    /** @description 작업의 폴링 타이머 정리. */
    clearJobTimer(job) {
        if (job?.pollTimer) {
            clearInterval(job.pollTimer);
            job.pollTimer = null;
        }
    }

    // ---------------- 작업 카드 액션 ----------------

    /** @description "명함 보기" 버튼 → BusinessCard 레코드 페이지로 네비게이션. */
    handleViewCard(event) {
        const job = this.findJob(Number(event.currentTarget.dataset.id));
        if (!job?.businessCardId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: job.businessCardId, objectApiName: 'BusinessCard__c', actionName: 'view' }
        });
    }

    /** @description "Lead 보기" 버튼 → 생성된 Lead 레코드 페이지로 네비게이션. */
    handleViewLead(event) {
        const job = this.findJob(Number(event.currentTarget.dataset.id));
        if (!job?.leadId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: job.leadId, objectApiName: 'Lead', actionName: 'view' }
        });
    }

    /** @description 작업 카드 우상단 × 버튼 → 해당 작업만 큐에서 제거. */
    handleDismissJob(event) {
        const id = Number(event.currentTarget.dataset.id);
        const job = this.findJob(id);
        if (job) this.clearJobTimer(job);
        this.jobs = this.jobs.filter(j => j.id !== id);
    }

    /** @description 큐 헤더의 정리 버튼 → 진행 중인 작업만 남기고 완료/실패 모두 제거. */
    handleClearCompleted() {
        this.jobs = this.jobs.filter(j => j.isActive);
    }

    // ---------------- helpers ----------------

    /** @returns {Object|undefined} ID로 job 조회 */
    findJob(id)              { return this.jobs.find(j => j.id === id); }

    /**
     * @description LWC reactivity를 보장하는 immutable update — jobs 배열을 통째로 교체.
     * @param {number} id 대상 job ID
     * @param {Object} patch 덮어쓸 필드들
     */
    updateJob(id, patch) {
        this.jobs = this.jobs.map(j => (j.id === id ? { ...j, ...patch } : j));
    }

    /**
     * @description 시작 이후 경과 시간을 사람이 읽기 쉽게 포맷.
     * @returns {string} "12s" 또는 "1m 5s"
     */
    formatElapsed(startedAt) {
        const sec = Math.round((Date.now() - startedAt) / 1000);
        return sec < 60 ? `${sec}s` : `${Math.floor(sec / 60)}m ${sec % 60}s`;
    }

    /** @description Salesforce Toast 알림. */
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ============== 이미지 전처리 (Resize + Sharpen + JPEG + Thumbnail) ==============

    /**
     * @description 클라이언트 측 이미지 전처리 파이프라인.
     *              Resize → Sharpen (실패 시 스킵) → JPEG 인코딩 → 썸네일 생성.
     *              네트워크/LLM 비용 절감 + OCR 정확도 향상이 목적.
     *
     * @param {File} file 원본 이미지
     * @returns {Promise<{base64: string, thumbnailUrl: string}>} 전처리 후 base64와 96px 썸네일 dataURL
     */
    async preprocessImage(file) {
        const dataUrl = await this.readAsDataURL(file);
        const img = await this.loadImage(dataUrl);

        const scale = Math.min(1, MAX_DIMENSION / Math.max(img.width, img.height));
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);

        const canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext('2d');
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(img, 0, 0, w, h);

        try {
            const imgData = ctx.getImageData(0, 0, w, h);
            const sharpened = this.applySharpen(imgData, SHARPEN_MIX);
            ctx.putImageData(sharpened, 0, 0);
        } catch (e) {
            // sharpen 실패 시 resize만으로 진행
        }

        const jpegDataUrl = canvas.toDataURL('image/jpeg', JPEG_QUALITY);
        const thumbnailUrl = this.makeThumbnail(canvas);
        return { base64: jpegDataUrl.split(',')[1], thumbnailUrl };
    }

    /**
     * @description UI 카드에 표시할 96px 썸네일 생성.
     * @param {HTMLCanvasElement} srcCanvas 전처리 완료된 원본 캔버스
     * @returns {string} JPEG dataURL
     */
    makeThumbnail(srcCanvas) {
        const TH = 96;
        const ratio = Math.min(TH / srcCanvas.width, TH / srcCanvas.height);
        const w = Math.round(srcCanvas.width * ratio);
        const h = Math.round(srcCanvas.height * ratio);
        const c = document.createElement('canvas');
        c.width = w;
        c.height = h;
        c.getContext('2d').drawImage(srcCanvas, 0, 0, w, h);
        return c.toDataURL('image/jpeg', 0.7);
    }

    /** @description File → dataURL Promise 래퍼. */
    readAsDataURL(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    /** @description dataURL → HTMLImageElement Promise 래퍼. */
    loadImage(src) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => resolve(img);
            img.onerror = () => reject(new Error('이미지 로드 실패'));
            img.src = src;
        });
    }

    /**
     * @description 3x3 unsharp-style convolution. 명함 텍스트 가독성을 위해 소프트 sharpening.
     * @param {ImageData} imageData 원본 픽셀 데이터
     * @param {number} mix 0~1, 0.35는 부드러운 sharpening
     * @returns {ImageData} sharpening 적용된 새 ImageData
     */
    applySharpen(imageData, mix) {
        const w = imageData.width;
        const h = imageData.height;
        const src = imageData.data;
        const dst = new Uint8ClampedArray(src.length);
        const kernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];

        dst.set(src);

        for (let y = 1; y < h - 1; y++) {
            for (let x = 1; x < w - 1; x++) {
                const center = (y * w + x) * 4;
                for (let c = 0; c < 3; c++) {
                    let sum = 0;
                    let ki = 0;
                    for (let ky = -1; ky <= 1; ky++) {
                        for (let kx = -1; kx <= 1; kx++) {
                            const idx = ((y + ky) * w + (x + kx)) * 4 + c;
                            sum += src[idx] * kernel[ki++];
                        }
                    }
                    const blended = src[center + c] * (1 - mix) + sum * mix;
                    dst[center + c] = blended < 0 ? 0 : blended > 255 ? 255 : blended;
                }
                dst[center + 3] = src[center + 3];
            }
        }
        return new ImageData(dst, w, h);
    }
}
