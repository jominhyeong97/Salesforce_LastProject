// Enable DebugLog TraceFlag for bot user (handosalesagent@...)
User u = [SELECT Id FROM User WHERE Username LIKE 'handosalesagent%' LIMIT 1];

// Cleanup existing flags for this user
delete [SELECT Id FROM TraceFlag WHERE TracedEntityId = :u.Id];

// Need a DebugLevel — reuse first available or create
DebugLevel dl;
List<DebugLevel> existing = [SELECT Id, DeveloperName FROM DebugLevel WHERE DeveloperName='SFDC_DevConsole' LIMIT 1];
if (!existing.isEmpty()) {
    dl = existing[0];
} else {
    dl = new DebugLevel(
        DeveloperName = 'AgentDebug',
        MasterLabel = 'AgentDebug',
        Apexcode = 'FINEST',
        Callout = 'INFO',
        Database = 'INFO',
        System = 'INFO',
        Validation = 'INFO',
        Visualforce = 'INFO',
        Workflow = 'INFO'
    );
    insert dl;
}

TraceFlag tf = new TraceFlag(
    TracedEntityId = u.Id,
    DebugLevelId = dl.Id,
    LogType = 'USER_DEBUG',
    StartDate = DateTime.now(),
    ExpirationDate = DateTime.now().addHours(2)
);
// TraceFlag insert needs Tooling API normally — try via Tooling SOAP through standard insert
try {
    insert tf;
    System.debug('TraceFlag created Id=' + tf.Id + ' (uses DebugLevel=' + dl.DeveloperName + ') expires=' + tf.ExpirationDate);
} catch (Exception e) {
    System.debug('Insert TraceFlag failed (expected — TraceFlag is Tooling API): ' + e.getMessage());
    System.debug('Use sf data create record --use-tooling-api instead');
}
