@IsTest
private class EmailTrackingService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Tracking Co.', Business_Number__c = '100-00-00009');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Tracking Opp', AccountId = acc.Id,
            StageName = '발굴', CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'TR-Q-001', OpportunityId = opp.Id,
            Status = '발송', ExpirationDate = Date.today().addDays(14),
            Sent_Date__c = Datetime.now().addHours(-1)
        );
        insert q;
    }

    private static RestRequest buildReq(Id quoteId, String action) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/quote-tracking/' + quoteId + '/' + action;
        req.httpMethod = 'GET';
        return req;
    }

    @IsTest
    static void testOpenPixel_updatesLastOpenedAt() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RestContext.request  = buildReq(q.Id, 'open.gif');
        RestContext.response = new RestResponse();

        Test.startTest();
        EmailTrackingService.handleGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('image/gif', RestContext.response.headers.get('Content-Type'));
        System.assertNotEquals(null, RestContext.response.responseBody, '픽셀 바디 반환');

        Quote refreshed = [SELECT Last_Opened_At__c, Last_Clicked_At__c FROM Quote WHERE Id = :q.Id];
        System.assertNotEquals(null, refreshed.Last_Opened_At__c, 'Last_Opened_At__c 갱신');
        System.assertEquals(null, refreshed.Last_Clicked_At__c, 'open 만 — Last_Clicked_At__c 미변경');
    }

    @IsTest
    static void testClick_redirects_andUpdatesBothFields() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RestContext.request  = buildReq(q.Id, 'click');
        RestContext.request.params.put('url', 'https://www.example.com/quote/details');
        RestContext.response = new RestResponse();

        Test.startTest();
        EmailTrackingService.handleGet();
        Test.stopTest();

        System.assertEquals(302, RestContext.response.statusCode, '302 redirect');
        System.assertEquals('https://www.example.com/quote/details',
            RestContext.response.headers.get('Location'), 'Location 헤더 = target URL');

        Quote refreshed = [SELECT Last_Opened_At__c, Last_Clicked_At__c FROM Quote WHERE Id = :q.Id];
        System.assertNotEquals(null, refreshed.Last_Clicked_At__c);
        System.assertNotEquals(null, refreshed.Last_Opened_At__c, 'click 은 open 도 갱신');
    }

    @IsTest
    static void testClick_noUrl_returns200() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RestContext.request  = buildReq(q.Id, 'click');
        RestContext.response = new RestResponse();

        Test.startTest();
        EmailTrackingService.handleGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertNotEquals(null, RestContext.response.responseBody);
    }

    @IsTest
    static void testInvalidId_returns400() {
        RestContext.request  = new RestRequest();
        RestContext.request.requestURI = '/services/apexrest/quote-tracking/notanid/open.gif';
        RestContext.request.httpMethod = 'GET';
        RestContext.response = new RestResponse();

        Test.startTest();
        EmailTrackingService.handleGet();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void testUnknownAction_returns404() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        RestContext.request  = buildReq(q.Id, 'random');
        RestContext.response = new RestResponse();

        Test.startTest();
        EmailTrackingService.handleGet();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @IsTest
    static void testNonexistentQuoteId_doesNotError() {
        Id fakeId = '0Q0000000000000';
        RestContext.request  = buildReq(fakeId, 'open.gif');
        RestContext.response = new RestResponse();

        Test.startTest();
        EmailTrackingService.handleGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode,
            '잘못된 Quote ID 도 픽셀은 반환 (트래킹 실패는 silent — fire-and-forget)');
    }
}
