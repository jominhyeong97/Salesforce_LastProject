({
    init: function(component) {
        var flow = component.find("flow");
        flow.startFlow("New_Lead_KR");
    },
    handleStatus: function(component, event) {
        if (event.getParam("status") === "FINISHED" || event.getParam("status") === "FINISHED_SCREEN") {
            var url = "/lightning/o/Lead/list";
            var navService = $A.get("e.force:navigateToURL");
            if (navService) {
                navService.setParams({ "url": url });
                navService.fire();
            }
        }
    }
})
