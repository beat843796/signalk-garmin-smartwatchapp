using Toybox.System;
using Toybox.WatchUi;

class AutopilotDelegate extends WatchUi.BehaviorDelegate {

	

	function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {

		var standbyItem = new WatchUi.MenuItem("Standby", null, AP_STATE_STANDBY, null);
		var autoItem = new WatchUi.MenuItem("Auto", null, AP_STATE_AUTO, null);
		var windItem = new WatchUi.MenuItem("Wind", null, AP_STATE_WIND, null);
		var trackItem = new WatchUi.MenuItem("Track", null, AP_STATE_TRACK, null);
		
		var focus = 0;
		
		switch ( vessel.autopilotState ) {
    		case "standby":
    			//standbyItem.setSubLabel("Current state");
    			focus = 0;
    			break;
    		case "auto":
    			autoItem.setSubLabel("Active");
    			focus = 1;
    			break;
    		case "wind": {
        		windItem.setSubLabel("Active");
        		focus = 2;
        		break;
    		}
    		case "route": {
        		trackItem.setSubLabel("Active");
        		focus = 3;
        		break;
    		}
		}
    	
    	
    	var menu = new WatchUi.Menu2({:title=>"SET MODE", :focus=>focus});

		menu.addItem(standbyItem);
        menu.addItem(autoItem);
        menu.addItem(windItem);
        menu.addItem(trackItem);

        WatchUi.pushView(menu, new AutopilotMenuDelegate(), WatchUi.SLIDE_UP );

        return true;

    }
    
    function onKey(keyEvent) {
 
        switch ( keyEvent.getKey() ) {
    		case KEY_DOWN:
    			vessel.autoPilotMinusOne();
    			break;
    		case KEY_UP:
    			vessel.autoPilotPlusOne();
    			break;
    		case KEY_CLOCK: {
        		vessel.autoPilotMinusTen();
        		break;
    		}
    		case KEY_MENU: {
        		vessel.autoPilotPlusTen();
        		break;
    		}
    		case KEY_ESC: {
        		WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        		break;
    		}

		}
		
		return true;
    }
}