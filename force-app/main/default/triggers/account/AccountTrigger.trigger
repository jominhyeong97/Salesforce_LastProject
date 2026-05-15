trigger AccountTrigger on Account (before insert, before update) {
    AccountTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}
