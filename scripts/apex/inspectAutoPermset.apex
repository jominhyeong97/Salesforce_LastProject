// Auto-created PermSet by sf agent create — 무엇을 갖고 있나
List<PermissionSet> autoPs = [SELECT Id, Name, Label FROM PermissionSet
                              WHERE Name LIKE 'HandoSalesAgent%' OR Label LIKE 'HandoSalesAgent%'];
for (PermissionSet ps : autoPs) {
    System.debug('PermSet=' + ps.Name + ' (' + ps.Label + ') Id=' + ps.Id);
    Integer apexN = 0;
    for (SetupEntityAccess s : [SELECT SetupEntityId, SetupEntityType FROM SetupEntityAccess
                                WHERE ParentId = :ps.Id AND SetupEntityType='ApexClass']) {
        ApexClass c = [SELECT Name FROM ApexClass WHERE Id=:s.SetupEntityId LIMIT 1];
        System.debug('  ApexClass: ' + c.Name);
        apexN++;
    }
    if (apexN == 0) System.debug('  (no ApexClass)');
    Integer objN = 0;
    for (ObjectPermissions op : [SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit
                                 FROM ObjectPermissions WHERE ParentId=:ps.Id]) {
        System.debug('  Object: ' + op.SobjectType + ' R=' + op.PermissionsRead + ' C=' + op.PermissionsCreate + ' E=' + op.PermissionsEdit);
        objN++;
    }
    if (objN == 0) System.debug('  (no Object perms)');
}

// 봇 user 로 직접 invocable 호출 가능한지 테스트
System.debug('=== Run Action as current user (admin) ===');
try {
    GetTodayPriorityListAction.Request r = new GetTodayPriorityListAction.Request();
    List<GetTodayPriorityListAction.Response> out = GetTodayPriorityListAction.run(
        new List<GetTodayPriorityListAction.Request>{r}
    );
    System.debug('  ✅ Action invoked OK as admin. count=' + out.size() + ' summary=' + (out.isEmpty() ? '?' : out[0].summary));
} catch (Exception e) {
    System.debug('  ❌ Exception: ' + e.getMessage());
}

// 자동 생성된 GenAiPlugin 확인
System.debug('=== GenAiPlugin (from Tooling API via SOQL fallback) ===');
// Note: GenAiPlugin/GenAiFunction are Tooling API objects — SOQL 가능 여부 확인용
try {
    Integer cntFn = [SELECT COUNT() FROM ApexClass WHERE Name IN ('GetTodayPriorityListAction','GetOrderAtRiskAction','GetAccountSummaryAction','DraftFollowupEmailAction')];
    System.debug('  Apex Action classes (4 expected): ' + cntFn);
} catch (Exception e) {
    System.debug('  SOQL error: ' + e.getMessage());
}
