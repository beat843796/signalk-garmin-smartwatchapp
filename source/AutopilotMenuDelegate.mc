using Toybox.WatchUi;
using Toybox.System;

class AutopilotMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        
        if(vessel.errorCode != null) {
			return true;
		}

		switch ( item.getId() ) {
    		case AP_STATE_STANDBY:
    			vessel.setAutopilotState("standby");
    			break;
    		case AP_STATE_AUTO:
    			vessel.setAutopilotState("auto");
    			break;
    		case AP_STATE_WIND: {
				vessel.setAutopilotState("wind");
        		break;
    		}
    		case AP_STATE_TRACK: {
				vessel.setAutopilotState("route");
        		break;
    		}
		}
        
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        
        return true;
    }
}