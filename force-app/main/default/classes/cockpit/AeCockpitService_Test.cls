@IsTest
private class AeCockpitService_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name='Cockpit Co.', Business_Number__c='100-00-00009',
            Long_Term_Debtor__c=true, Total_AR__c=8000000
        );
        insert acc;

        // 신규 Lead 2건
        insert new List<Lead>{
            new Lead(LastName='김', Company='RFQ 신규1', Status='신규',
                     Source_Channel__c='EMAIL', Lead_Score__c=80),
            new Lead(LastName='박', Company='RFQ 신규2', Status='제안대기',
                     Source_Channel__c='PHONE', Lead_Score__c=65)
        };

        // 발송 Quote 1건
        Id stdPb = Test.getStandardPricebookId();
        Opportunity opp = new Opportunity(
            Name='Cockpit Opp', AccountId=acc.Id, StageName='견적 발송',
            CloseDate=Date.today().addDays(30), Pricebook2Id=stdPb
        );
        insert opp;
        Quote q = new Quote(
            Name='Q-COCKPIT', OpportunityId=opp.Id, Pricebook2Id=stdPb,
            Status='발송', Sent_Date__c=DateTime.now().addDays(-2)
        );
        insert q;

        // 위험 Order 1건
        insert new Order(
            AccountId=acc.Id, EffectiveDate=Date.today(), Status='Draft',
            Pricebook2Id=stdPb, PoNumber='PO-COCKPIT-R',
            Production_Status__c='InProgress', Delivery_Risk_Score__c=88,
            Last_ErpSync_At__c=DateTime.now()
        );
    }

    @IsTest
    static void testLoad_returnsAllFiveSections() {
        Test.startTest();
        AeCockpitService.Dashboard d = AeCockpitService.load();
        Test.stopTest();

        System.assertEquals(1, d.newRfqs.size(), 'Status=신규 Lead 1건 (제안대기는 제외)');
        System.assertEquals(2, d.priorityLeads.size(), '신규+제안대기 우선 Lead 2건');
        System.assertEquals(1, d.sentQuotes.size(), '발송 Quote 1건');
        System.assertEquals(1, d.riskyOrders.size(), '위험 Order 1건');
        System.assertEquals(1, d.arActions.size(), '미수금 Account 1건');
    }

    @IsTest
    static void testLoad_priorityLeads_sortedByScoreDesc() {
        AeCockpitService.Dashboard d = AeCockpitService.load();

        System.assertEquals(80, d.priorityLeads[0].leadScore, '점수 높은 순');
        System.assertEquals(65, d.priorityLeads[1].leadScore);
    }

    @IsTest
    static void testLoad_riskyOrders_onlyHighRisk() {
        // 안전 Order 추가
        Account a = [SELECT Id FROM Account LIMIT 1];
        Id stdPb = Test.getStandardPricebookId();
        insert new Order(
            AccountId=a.Id, EffectiveDate=Date.today(), Status='Draft',
            Pricebook2Id=stdPb, PoNumber='PO-COCKPIT-OK',
            Production_Status__c='Shipped', Delivery_Risk_Score__c=10
        );

        Test.startTest();
        AeCockpitService.Dashboard d = AeCockpitService.load();
        Test.stopTest();

        System.assertEquals(1, d.riskyOrders.size(), '위험 ≥70 만 포함');
        System.assertEquals(88, d.riskyOrders[0].riskScore);
    }

    @IsTest
    static void testLoad_arActions_longTermFlag() {
        AeCockpitService.Dashboard d = AeCockpitService.load();
        System.assertEquals(true, d.arActions[0].isLongTerm);
        System.assertEquals(8000000, d.arActions[0].totalAR);
    }

    @IsTest
    static void testStagePipeline_groupsByStage() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Id stdPb = Test.getStandardPricebookId();

        // 발굴 3건 / 견적 작성 2건 / 협상 1건
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opps.add(new Opportunity(
                Name='Pipe-발굴-'+i, AccountId=a.Id,
                StageName='발굴', CloseDate=Date.today().addDays(30),
                Amount=1000000, Pricebook2Id=stdPb
            ));
        }
        for (Integer i = 0; i < 2; i++) {
            opps.add(new Opportunity(
                Name='Pipe-견적-'+i, AccountId=a.Id,
                StageName='견적 작성', CloseDate=Date.today().addDays(30),
                Amount=2000000, Pricebook2Id=stdPb
            ));
        }
        opps.add(new Opportunity(
            Name='Pipe-협상-1', AccountId=a.Id,
            StageName='협상', CloseDate=Date.today().addDays(30),
            Amount=5000000, Pricebook2Id=stdPb
        ));
        insert opps;

        Test.startTest();
        AeCockpitService.Dashboard d = AeCockpitService.load();
        Test.stopTest();

        System.assertEquals(5, d.stagePipeline.size(), '5 단계 모두 반환');
        Map<String, AeCockpitService.PipelineStage> byStage = new Map<String, AeCockpitService.PipelineStage>();
        for (AeCockpitService.PipelineStage p : d.stagePipeline) byStage.put(p.stageName, p);

        System.assertEquals(3, byStage.get('발굴').oppCount);
        System.assertEquals(3000000, byStage.get('발굴').totalAmount);
        System.assertEquals(2, byStage.get('견적 작성').oppCount);
        // 견적 발송 — TestSetup 의 'Cockpit Opp' 1건이 존재
        System.assertEquals(1, byStage.get('견적 발송').oppCount);
        System.assertEquals(1, byStage.get('협상').oppCount);
        System.assertEquals(5000000, byStage.get('협상').totalAmount);
        // 데이터 없는 단계도 0 으로 반환되는지 (수주)
        System.assertEquals(0, byStage.get('수주').oppCount);
        // 수주 단계는 setup 의 testLoad 케이스가 추가하지 않으면 0
    }

    @IsTest
    static void testDueLabel_returnsCorrectFormat() {
        Date today = Date.today();
        System.assertEquals('', AeCockpitService.dueLabel(null));
        System.assert(AeCockpitService.dueLabel(today.addDays(-3)).contains('초과'),
            'overdue label expected');
        System.assert(AeCockpitService.dueLabel(today.addDays(-3)).contains('D+3'),
            'D+3 label expected');
        System.assertEquals('⏰ D-day', AeCockpitService.dueLabel(today));
        System.assertEquals('🔥 D-1', AeCockpitService.dueLabel(today.addDays(1)));
        System.assertEquals('🔥 D-3', AeCockpitService.dueLabel(today.addDays(3)));
        System.assertEquals('D-7', AeCockpitService.dueLabel(today.addDays(7)));
    }

    @IsTest
    static void testLoad_riskyOrders_includesDueLabel() {
        // 위험 Order 의 EffectiveDate + EndDate 모두 과거 시점으로 갱신 (overdue 시연)
        Order existing = [SELECT Id FROM Order WHERE PoNumber = 'PO-COCKPIT-R' LIMIT 1];
        existing.EffectiveDate = Date.today().addDays(-10);
        existing.EndDate       = Date.today().addDays(-2);
        update existing;

        Test.startTest();
        AeCockpitService.Dashboard d = AeCockpitService.load();
        Test.stopTest();

        System.assertEquals(1, d.riskyOrders.size());
        System.assertEquals(Date.today().addDays(-2), d.riskyOrders[0].endDate);
        System.assert(d.riskyOrders[0].dueLabel.contains('초과'),
            'overdue label expected, got: ' + d.riskyOrders[0].dueLabel);
    }

    @IsTest
    static void testLoad_emptyOrg_emptyLists() {
        // Setup 데이터 모두 삭제
        delete [SELECT Id FROM Lead];
        delete [SELECT Id FROM Quote];
        delete [SELECT Id FROM Order];
        delete [SELECT Id FROM Opportunity];
        Account a = [SELECT Id FROM Account LIMIT 1];
        a.Long_Term_Debtor__c = false;
        a.Total_AR__c = 0;
        update a;

        Test.startTest();
        AeCockpitService.Dashboard d = AeCockpitService.load();
        Test.stopTest();

        System.assertEquals(0, d.newRfqs.size());
        System.assertEquals(0, d.priorityLeads.size());
        System.assertEquals(0, d.sentQuotes.size());
        System.assertEquals(0, d.riskyOrders.size());
        System.assertEquals(0, d.arActions.size());
    }
}
