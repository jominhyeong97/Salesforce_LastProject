/**
 * QuoteEmailService — Quote PDF + 사용자 편집 가능한 제목/본문으로 이메일 발송.
 * 신용한도 차단 없음 (FR-QUOTE-005).
 *
 * @group Quote
 */
public with sharing class QuoteEmailService {

    /**
     * 이메일 모달의 default 제목·본문 — LWC가 모달 열 때 받아서 input에 채움.
     */
    @AuraEnabled(cacheable=true)
    public static EmailDefaultDTO getDefaultEmail(Id quoteId) {
        if (quoteId == null) throw newAura('quoteId is required');
        Quote q = [
            SELECT Id, Name, Account.Name, Opportunity.Name
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];
        String accName = (q.Account != null && q.Account.Name != null) ? q.Account.Name : '고객사';
        String oppName = (q.Opportunity != null && q.Opportunity.Name != null) ? q.Opportunity.Name : '귀사 안건';

        EmailDefaultDTO dto = new EmailDefaultDTO();
        dto.subject = '[' + accName + '] 견적서 ' + q.Name;
        dto.body =
            accName + ' 담당자님, 안녕하세요.\n\n' +
            '요청하신 ' + oppName + ' 건의 견적서를 첨부드립니다. ' +
            '첨부 파일을 확인하시고 회신 부탁드립니다.\n\n' +
            '문의 사항이 있으시면 회신 메일로 알려 주세요.\n\n' +
            '감사합니다.\n한도정밀 영업팀';
        return dto;
    }

    @AuraEnabled
    public static Id sendQuote(Id quoteId, String toEmail, Id contentDocumentId, String subject, String body) {
        if (quoteId == null)            throw newAura('quoteId is required');
        if (String.isBlank(toEmail))    throw newAura('toEmail is required');
        if (contentDocumentId == null)  throw newAura('contentDocumentId (PDF) is required — 먼저 PDF를 생성하세요');

        Quote q = [
            SELECT Id, Name, Status, OpportunityId, Account.Name, Opportunity.Name, Opportunity.StageName
            FROM Quote WHERE Id = :quoteId LIMIT 1
        ];

        // 기본값 fallback
        if (String.isBlank(subject)) {
            subject = '[' + (q.Account != null ? q.Account.Name : '고객사') + '] 견적서 ' + q.Name;
        }
        if (String.isBlank(body)) {
            body = '견적서를 첨부드립니다.\n한도정밀 영업팀';
        }

        // plain text → HTML (XSS 방지 escape + 줄바꿈)
        String htmlBody = body.escapeHtml4().replace('\n', '<br/>');

        // FR-QUOTE-006 — 추적 픽셀 + 링크 wrap. Custom Label Quote_Tracking_Base_URL 미설정 시 skip.
        String trackingBase = trackingBaseUrl();
        if (String.isNotBlank(trackingBase)) {
            htmlBody = autoLinkAndWrap(htmlBody, q.Id, trackingBase)
                + '<img src="' + trackingBase + '/' + q.Id + '/open.gif" '
                + 'width="1" height="1" alt="" style="display:none"/>';
        }

        ContentVersion cv = [
            SELECT Id, VersionData, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];

        Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
        attach.setFileName(cv.Title + '.pdf');
        attach.setBody(cv.VersionData);
        attach.setContentType('application/pdf');

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ toEmail });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setFileAttachments(new Messaging.EmailFileAttachment[]{ attach });

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ email });
        }

        q.Status = '발송';
        q.Sent_Date__c = Datetime.now();
        try {
            update q;
        } catch (DmlException e) {
            throw newAura('Quote 상태 갱신 실패: ' + e.getDmlMessage(0));
        }

        // FR-OPP-002 — Quote 발송 시 Opportunity Stage 자동 전이 '견적 작성' → '견적 발송'.
        // 이후 단계('협상'/'수주'/'실주') 이미 진행 중이면 건드리지 않음.
        if (q.OpportunityId != null && q.Opportunity != null
                && q.Opportunity.StageName == '견적 작성') {
            try {
                update new Opportunity(Id = q.OpportunityId, StageName = '견적 발송');
            } catch (DmlException e) {
                // Stage 게이트 등에 막혀도 Quote 발송 자체는 성공 — 부수 효과는 silent skip
                System.debug(LoggingLevel.WARN, 'Opp stage auto-transition skipped: ' + e.getDmlMessage(0));
            }
        }

        return q.Id;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Email tracking helpers (FR-QUOTE-006)
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Custom Label Quote_Tracking_Base_URL — 비어있거나 sentinel(__UNSET__) 이면 추적 미사용.
     * Site 배포 후 사용자가 https://{site}.../services/apexrest/quote-tracking 로 갱신.
     */
    @TestVisible
    private static String trackingBaseUrl() {
        try {
            String url = System.Label.Quote_Tracking_Base_URL;
            if (String.isBlank(url) || !url.startsWith('http')) return null;
            return url.removeEnd('/');
        } catch (Exception e) {
            return null;
        }
    }

    /** 본문의 http(s) URL 을 추적용 click endpoint 로 wrap 한 <a> 태그로 변환. */
    @TestVisible
    private static String autoLinkAndWrap(String body, Id quoteId, String base) {
        if (String.isBlank(body) || String.isBlank(base)) return body;
        Pattern p = Pattern.compile('(https?://[^\\s<>"]+)');
        Matcher m = p.matcher(body);
        String prefix = base + '/' + quoteId + '/click?url=';
        return m.replaceAll('<a href="' + prefix + '$1">$1</a>');
    }

    private static AuraHandledException newAura(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        return e;
    }

    public class EmailDefaultDTO {
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
    }
}
