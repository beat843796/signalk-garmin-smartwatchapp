using Toybox.WatchUi;
using Toybox.System;

class AutopilotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        System.println(item.getId());

		vessel.setAutopilotState(item.getId());
        
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        
    }
}