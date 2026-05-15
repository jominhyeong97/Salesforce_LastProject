// Diagnose: Agentforce user 권한 + Apex classAccess + PermSet assignments
List<User> agents = [SELECT Id, Username, Profile.Name, UserType, IsActive
                     FROM User
                     WHERE Username LIKE 'handosalesagent%'];
System.debug('=== Agent Users ===');
for (User u : agents) {
    System.debug('  ' + u.Username + ' | Profile=' + u.Profile.Name + ' | Type=' + u.UserType + ' | Active=' + u.IsActive);
}
if (agents.isEmpty()) {
    System.debug('NO agent user found.');
    return;
}
Id agentId = agents[0].Id;

System.debug('=== PermSetAssignment for agent ===');
List<PermissionSetAssignment> psas = [
    SELECT Id, PermissionSet.Name, PermissionSet.Label, PermissionSet.IsCustom,
           PermissionSetGroup.DeveloperName
    FROM PermissionSetAssignment
    WHERE AssigneeId = :agentId
];
for (PermissionSetAssignment psa : psas) {
    System.debug('  PS: ' + psa.PermissionSet.Name + ' (Label=' + psa.PermissionSet.Label + ', Custom=' + psa.PermissionSet.IsCustom + ', Group=' + psa.PermissionSetGroup.DeveloperName + ')');
}

System.debug('=== Apex classAccess for our 4 Actions + AeCockpitService (via PermSets) ===');
List<String> targetClasses = new List<String>{
    'GetTodayPriorityListAction','GetOrderAtRiskAction',
    'GetAccountSummaryAction','DraftFollowupEmailAction','AeCockpitService'
};
List<SetupEntityAccess> seas = [
    SELECT Id, ParentId, Parent.Name, Parent.Profile.Name,
           SetupEntityId, SetupEntityType
    FROM SetupEntityAccess
    WHERE SetupEntityType = 'ApexClass'
      AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :agentId)
];
// map class id → name
Map<Id, String> classMap = new Map<Id, String>();
for (ApexClass c : [SELECT Id, Name FROM ApexClass WHERE Name IN :targetClasses]) {
    classMap.put(c.Id, c.Name);
}
Set<String> foundClasses = new Set<String>();
for (SetupEntityAccess s : seas) {
    String cn = classMap.get(s.SetupEntityId);
    if (cn != null) {
        foundClasses.add(cn);
        System.debug('  ✅ ' + cn + ' via PermSet ' + s.Parent.Name);
    }
}
for (String tc : targetClasses) {
    if (!foundClasses.contains(tc)) {
        System.debug('  ❌ MISSING: ' + tc);
    }
}

System.debug('=== Bot definition ===');
List<BotDefinition> bots = [SELECT Id, DeveloperName, MasterLabel, Type, AgentType FROM BotDefinition WHERE DeveloperName='HandoSalesAgent'];
for (BotDefinition b : bots) {
    System.debug('  Bot=' + b.DeveloperName + ' (' + b.MasterLabel + ') Type=' + b.Type + ' AgentType=' + b.AgentType);
}

System.debug('=== BotVersion ===');
for (BotVersion bv : [SELECT Id, Status, DeveloperName, BotDefinitionId
                      FROM BotVersion WHERE BotDefinition.DeveloperName='HandoSalesAgent']) {
    System.debug('  v=' + bv.DeveloperName + ' Status=' + bv.Status + ' Id=' + bv.Id);
}

System.debug('=== UserLicense / Profile of agent ===');
for (User u : [SELECT Id, Username, ProfileId, UserType, Profile.UserLicense.Name FROM User WHERE Id=:agentId]) {
    System.debug('  License=' + u.Profile.UserLicense.Name + ' UserType=' + u.UserType);
}
