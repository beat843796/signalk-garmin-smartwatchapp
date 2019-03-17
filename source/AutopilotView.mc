using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;

using Utilities as Utils;

class AutopilotView extends WatchUi.View {

	var rudderHeight = 26;
	var width;
    var height;
        
    function initialize() {
        View.initialize();

    }


    // Update the view
    function onUpdate(dc) {
        
        View.onUpdate(dc);
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);

        dc.clear();
        
        width = dc.getWidth();
        height = dc.getHeight();
        var blockHeight = height/3;
        
		drawValues(dc);
        

    }
    

    function drawValues(dc) {
    
    	// DRAW TEXT
        
        var valueToDraw = "---";
        var labelText = "";
        var stateName = vessel.getNameForActiveState();
        
        switch ( vessel.autopilotState ) {
    		case "standby":
    			valueToDraw = vessel.getHeadingDegreeString();
    			labelText = "HDG";
    		
    			break;
    		case "auto":
    			valueToDraw = vessel.getTargetHeadingTrueDegreeString();
    			labelText = "HDG";
    	
    			break;
    		case "wind": {
        		valueToDraw = vessel.getTargetHeadingWindAppearantDegreeString();
        		labelText = "AWA";
        		        		break;
    		}
    		case "route": {
        		valueToDraw = "3.6";
        		labelText = "DTW";
        		break;
    		}
		}


        drawDataText(dc,width/2,10,labelText,valueToDraw);
        
        if(vessel.autopilotState.equals("standby")) {
        	dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);
        } else {
        	dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_WHITE);
        }
        

		if(vessel.errorCode != null) {
			
			dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_WHITE);
			stateName = "ERROR";
			
		
		}

        dc.drawText(
        width/2,                     
        165,                   
        Graphics.FONT_SYSTEM_MEDIUM,     
        stateName,                   
        Graphics.TEXT_JUSTIFY_CENTER);
        
        // DRAW RUDDER ANGLE VIEW
        
        drawRudderAngle(dc, Utils.radiansToDegrees(vessel.rudderAngle));
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);
        dc.setPenWidth(2);
        
        var xOffsetTens = width/8;
        
        for( var i = 1; i < 8; i += 1 ) {
        	dc.drawLine(0+xOffsetTens*i, height/2-rudderHeight/2, +xOffsetTens*i, height/2+rudderHeight/2);
        }
                
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);
        dc.setPenWidth(4);
        
        dc.drawLine(0, height/2-rudderHeight/2, width, height/2-rudderHeight/2);
        dc.drawLine(0, height/2+rudderHeight/2, width, height/2+rudderHeight/2);

        dc.drawLine(width/2, height/2-rudderHeight/2, width/2, height/2+rudderHeight/2);
        
        dc.setColor(Graphics.COLOR_ORANGE,Graphics.COLOR_WHITE);
        Utils.drawWindAngle(dc,vessel.apparentWindAngle,width);
    
    }
    
    function drawDataText(dc,x,y,labelText,valueText) {
    
    	dc.drawText(
        x,                     
        y-2,                   
        Graphics.FONT_SYSTEM_XTINY,     
        labelText,                   
        Graphics.TEXT_JUSTIFY_CENTER);
        
        dc.drawText(
        x,                      
        y+28,                     
        Graphics.FONT_NUMBER_HOT,       
        valueText,                         
        Graphics.TEXT_JUSTIFY_CENTER);
    
    }
	
	function drawRudderAngle(dc, rudderAngle) {
	
		// nothing to draw
		if(rudderAngle == 0) {
			return;
		}
	
		var absRudderAngle = rudderAngle;
		
		if(rudderAngle < 0) {
			absRudderAngle = rudderAngle * -1;
		}
	
		var percentage = absRudderAngle / 40.0d;
		
		
		
		if(percentage > 1.0d) {
			percentage = 1.0;
		}
		
		if(rudderAngle < 0) {
			dc.setColor(Graphics.COLOR_DK_GREEN,Graphics.COLOR_WHITE);
		} else {
			dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_WHITE);
		}
	
	
		var xOffset = 0;
		
		if(rudderAngle < 0.0d) {
			xOffset = width/2*percentage;
		}
		
		dc.fillRectangle(width/2-xOffset, height/2-rudderHeight/2, width/2*percentage, rudderHeight);
		
		
	
	}
	

}

class AutopilotDelegate extends WatchUi.BehaviorDelegate {

	

	function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {

		if(vessel.errorCode != null) {
			return true;
		}

		var standbyItem = new WatchUi.MenuItem("Standby", null, AP_STATE_STANDBY, null);
		var autoItem = new WatchUi.MenuItem("Auto", null, AP_STATE_AUTO, null);
		var windItem = new WatchUi.MenuItem("Wind", null, AP_STATE_WIND, null);
		var trackItem = new WatchUi.MenuItem("Track", null, AP_STATE_TRACK, null);
		
		var focus = 0;
		
		switch ( vessel.autopilotState ) {
    		case "standby":
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
    			vessel.changeHeading(-1);
    			break;
    		case KEY_UP:
    			vessel.changeHeading(+1);
    			break;
    		case KEY_CLOCK: {
        		vessel.changeHeading(-10);
        		break;
    		}
    		case KEY_MENU: {
        		vessel.changeHeading(+10);
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
