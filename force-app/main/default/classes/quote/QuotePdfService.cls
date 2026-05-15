/**
 * QuotePdfService — Quote → PDF (ContentVersion) 생성·첨부.
 * Visualforce QuotePdfPage가 PricingService 합계까지 렌더링.
 *
 * @group Quote
 */
public with sharing class QuotePdfService {

    /**
     * Quote에 이미 첨부된 우리 PDF 중 가장 최근 ContentDocumentId 반환.
     * 페이지 로드 시 LWC가 호출해서 [이메일 발송] 버튼을 옛 PDF로도 즉시 활성화.
     */
    @AuraEnabled(cacheable=true)
    public static Id getLatestPdfId(Id quoteId) {
        if (quoteId == null) return null;
        Quote q = [SELECT Name FROM Quote WHERE Id = :quoteId LIMIT 1];
        String prefix = q.Name + '_견적서';
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, SystemModstamp
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :quoteId
                AND ContentDocument.Title LIKE :prefix + '%'
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].ContentDocumentId;
    }

    @AuraEnabled
    public static Id generatePdf(Id quoteId) {
        if (quoteId == null) {
            throw newAura('quoteId is required');
        }

        Quote q = [SELECT Id, Name FROM Quote WHERE Id = :quoteId LIMIT 1];
        String titlePrefix = q.Name + '_견적서';

        // 1. 옛 우리 PDF 삭제 (단일 최신 유지)
        deleteExistingPdfs(quoteId, titlePrefix);

        // 2. 새 PDF 생성
        Blob pdfBlob;
        if (Test.isRunningTest()) {
            pdfBlob = Blob.valueOf('TEST PDF CONTENT — ' + q.Name);
        } else {
            PageReference pg = Page.QuotePdfPage;
            pg.getParameters().put('id', quoteId);
            pdfBlob = pg.getContentAsPDF();
        }

        ContentVersion cv = new ContentVersion(
            Title           = titlePrefix,
            PathOnClient    = q.Name + '.pdf',
            VersionData     = pdfBlob,
            ContentLocation = 'S'
        );
        try {
            insert cv;
        } catch (DmlException e) {
            throw newAura('PDF 저장 실패: ' + e.getDmlMessage(0));
        }

        Id cdId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cdId,
            LinkedEntityId    = quoteId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        try {
            insert cdl;
        } catch (DmlException e) {
            throw newAura('PDF 첨부 실패: ' + e.getDmlMessage(0));
        }

        return cdId;
    }

    /**
     * Quote에 첨부된 우리 패턴의 옛 PDF 모두 삭제.
     * 사용자 업로드 PDF나 사업자등록증 같은 다른 첨부는 보존.
     */
    @TestVisible
    private static void deleteExistingPdfs(Id quoteId, String titlePrefix) {
        Set<Id> oldCdIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :quoteId
                AND ContentDocument.Title LIKE :titlePrefix + '%'
        ]) {
            oldCdIds.add(link.ContentDocumentId);
        }
        if (!oldCdIds.isEmpty()) {
            try {
                delete [SELECT Id FROM ContentDocument WHERE Id IN :oldCdIds];
            } catch (DmlException e) {
                // 삭제 실패해도 새 PDF 생성은 진행 — silently 무시
            }
        }
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }
}
