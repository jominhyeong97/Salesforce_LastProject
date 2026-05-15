/**
 * @description LLM 호출 + 매핑 + Lead 생성을 비동기로 처리하는 Queueable.
 *              {@link AutoLeadByBC_Service.enqueueProcessing}이 BusinessCard와 ContentVersion을
 *              먼저 만든 뒤 enqueueJob(this) 한다. execute에서 동기 작업을 이어서 수행.
 *
 * @group AutoLeadByBC
 *
 * @see AutoLeadByBC_Service
 */
public class BC_ProcessQueueable implements Queueable, Database.AllowsCallouts {
    private final Id businessCardId;
    private final Id contentDocumentId;

    /**
     * @description Queueable 인스턴스 생성. 즉시 실행되지 않고 System.enqueueJob 시점에 큐에 들어간다.
     * @param businessCardId    Status='Queued' 상태의 BusinessCard__c Id
     * @param contentDocumentId BusinessCard에 연결된 명함 이미지 ContentDocument Id
     */
    public BC_ProcessQueueable(Id businessCardId, Id contentDocumentId) {
        this.businessCardId = businessCardId;
        this.contentDocumentId = contentDocumentId;
    }

    /**
     * @description Queueable 진입점. 실제 작업은 AutoLeadByBC_Service.processInBackground에 위임.
     * @param ctx Salesforce 플랫폼이 주입하는 Queueable 컨텍스트
     */
    public void execute(QueueableContext ctx) {
        AutoLeadByBC_Service.processInBackground(businessCardId, contentDocumentId);
    }
}
