@isTest
private class RfqInboundHandlerTest {

    private static Messaging.InboundEnvelope makeEnv(String fromAddr) {
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        env.fromAddress = fromAddr;
        env.toAddress = 'rfq@hando.example';
        return env;
    }

    @isTest
    static void testFullEmailCreatesLead() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'kim@hyundai-mobis.example';
        email.fromName = '현대모비스 김 과장';
        email.subject = 'RFQ 베어링 6204 100개';
        email.plainTextBody = '안녕하세요. 베어링 6204 100개 견적 부탁드립니다. 다음달 말까지 회신 부탁드립니다.';

        Test.startTest();
        Messaging.InboundEmailResult r = new RfqInboundHandler().handleInboundEmail(email, makeEnv(email.fromAddress));
        Test.stopTest();

        System.assert(r.success, 'Result message: ' + r.message);

        Lead l = [
            SELECT Id, Source_Channel__c, Email, Company, RFQ_Spec_JSON__c, Description
            FROM Lead WHERE Email = :email.fromAddress LIMIT 1
        ];
        System.assertEquals('EMAIL', l.Source_Channel__c);
        System.assertEquals(email.fromAddress, l.Email);
        System.assert(l.Description.contains('RFQ'), 'Description: ' + l.Description);
        System.assert(l.RFQ_Spec_JSON__c.contains('100') || l.RFQ_Spec_JSON__c.contains('베어링'),
            'Spec: ' + l.RFQ_Spec_JSON__c);
    }

    @isTest
    static void testNoFromNameFallsBackToDomain() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'unknown@example.com';
        email.subject = 'RFQ';
        email.plainTextBody = ''; // 빈 본문

        Test.startTest();
        Messaging.InboundEmailResult r = new RfqInboundHandler().handleInboundEmail(email, makeEnv(email.fromAddress));
        Test.stopTest();

        System.assert(r.success, r.message);
        Lead l = [SELECT Company, LastName FROM Lead WHERE Email = :email.fromAddress LIMIT 1];
        System.assertEquals('example', l.Company);
        System.assertEquals(email.fromAddress, l.LastName);
    }

    @isTest
    static void testExtractDomain() {
        System.assertEquals('hyundai-mobis', RfqInboundHandler.extractDomain('a@hyundai-mobis.co.kr'));
        System.assertEquals('Unknown', RfqInboundHandler.extractDomain('no-at-sign'));
        System.assertEquals('Unknown', RfqInboundHandler.extractDomain(null));
        System.assertEquals('Unknown', RfqInboundHandler.extractDomain(''));
    }

    @isTest
    static void testEmailLeadHasScore() {
        // EMAIL 채널 20 + 사양 10 + quantity 10 = 40 (과거 거래 없을 때)
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'buyer@scoretest.example';
        email.fromName = 'Buyer';
        email.subject = 'RFQ';
        email.plainTextBody = '베어링 6204 100개 견적 부탁';

        Test.startTest();
        Messaging.InboundEmailResult r = new RfqInboundHandler().handleInboundEmail(email, makeEnv(email.fromAddress));
        Test.stopTest();
        System.assert(r.success, r.message);

        Lead l = [SELECT Lead_Score__c FROM Lead WHERE Email = :email.fromAddress LIMIT 1];
        System.assertNotEquals(null, l.Lead_Score__c, 'Score 미계산');
        System.assert(l.Lead_Score__c.intValue() >= 20, 'EMAIL 기본 20 이상이어야: ' + l.Lead_Score__c);
    }

    @isTest
    static void testFromNameUsedWhenBodyMissing() {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = 'park@somewhere.example';
        email.fromName = '대성기공';
        email.subject = 'inquiry';
        email.plainTextBody = null;

        Test.startTest();
        Messaging.InboundEmailResult r = new RfqInboundHandler().handleInboundEmail(email, makeEnv(email.fromAddress));
        Test.stopTest();

        System.assert(r.success);
        Lead l = [SELECT Company FROM Lead WHERE Email = :email.fromAddress LIMIT 1];
        System.assertEquals('대성기공', l.Company);
    }
}
