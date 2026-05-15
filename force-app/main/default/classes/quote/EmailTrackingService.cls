/**
 * EmailTrackingService — Quote 이메일 추적용 공개 REST 엔드포인트 (FR-QUOTE-006).
 *
 * URL 매핑 (Force.com Site 경유):
 *   /services/apexrest/quote-tracking/{quoteId}/open.gif  → 1x1 투명 GIF + Last_Opened_At__c 갱신
 *   /services/apexrest/quote-tracking/{quoteId}/click?url=...  → 302 redirect + Last_Clicked_At__c 갱신
 *
 * Site Guest User 가 Quote write 권한을 가져야 동작.
 * Setup: Setup → Sites → New → Apex Class Access 에 EmailTrackingService 추가 → Object Settings 에서 Quote Edit 허용.
 *
 * @group Quote
 */
@RestResource(urlMapping='/quote-tracking/*')
global without sharing class EmailTrackingService {

    /** 1x1 투명 GIF — open pixel response */
    private static final Blob TRANSPARENT_PIXEL = EncodingUtil.base64Decode(
        'R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==');

    @TestVisible private static Datetime lastRecordedAt;  // 테스트 검증용

    @HttpGet
    global static void handleGet() {
        RestRequest req = RestContext.request;
        RestResponse resp = RestContext.response;
        if (req == null || resp == null) return;

        List<String> parts = req.requestURI.split('/');
        // 예상: /services/apexrest/quote-tracking/{quoteId}/{action}
        if (parts.size() < 2) {
            resp.statusCode = 400; return;
        }
        String action = parts[parts.size() - 1].toLowerCase();
        String rawId  = parts[parts.size() - 2];
        Id quoteId;
        try { quoteId = (Id) rawId; }
        catch (Exception e) { resp.statusCode = 400; return; }

        if (action.startsWith('open')) {
            handleOpen(quoteId, resp);
        } else if (action.startsWith('click')) {
            handleClick(quoteId, req, resp);
        } else {
            resp.statusCode = 404;
        }
    }

    @TestVisible
    private static void handleOpen(Id quoteId, RestResponse resp) {
        recordOpen(quoteId);
        resp.statusCode = 200;
        resp.headers.put('Content-Type', 'image/gif');
        resp.headers.put('Cache-Control', 'no-cache, no-store, must-revalidate');
        resp.headers.put('Pragma', 'no-cache');
        resp.responseBody = TRANSPARENT_PIXEL;
    }

    @TestVisible
    private static void handleClick(Id quoteId, RestRequest req, RestResponse resp) {
        String targetUrl = req.params.get('url');
        recordClick(quoteId);
        if (String.isNotBlank(targetUrl)) {
            resp.statusCode = 302;
            resp.headers.put('Location', targetUrl);
        } else {
            resp.statusCode = 200;
            resp.responseBody = Blob.valueOf('Tracking recorded.');
        }
    }

    private static void recordOpen(Id quoteId) {
        if (quoteId == null) return;
        try {
            Quote q = new Quote(Id = quoteId, Last_Opened_At__c = Datetime.now());
            update q;
            lastRecordedAt = Datetime.now();
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'recordOpen failed for ' + quoteId + ': ' + e.getMessage());
        }
    }

    private static void recordClick(Id quoteId) {
        if (quoteId == null) return;
        try {
            Quote q = new Quote(
                Id = quoteId,
                Last_Clicked_At__c = Datetime.now(),
                Last_Opened_At__c  = Datetime.now()   // click 은 open 도 의미
            );
            update q;
            lastRecordedAt = Datetime.now();
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'recordClick failed for ' + quoteId + ': ' + e.getMessage());
        }
    }
}
