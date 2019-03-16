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
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        
        var xOffsetTens = width/8;
        
        for( var i = 1; i < 8; i += 1 ) {
        	dc.drawLine(0+xOffsetTens*i, height/2-rudderHeight/2, +xOffsetTens*i, height/2+rudderHeight/2);
        }
                
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        
        dc.drawLine(0, height/2-rudderHeight/2, width, height/2-rudderHeight/2);
        dc.drawLine(0, height/2+rudderHeight/2, width, height/2+rudderHeight/2);

        dc.drawLine(width/2, height/2-rudderHeight/2, width/2, height/2+rudderHeight/2);
        
        dc.setColor(Graphics.COLOR_ORANGE,Graphics.COLOR_TRANSPARENT);
        drawWindAngle(dc,vessel.apparentWindAngle);
    
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
			dc.setColor(Graphics.COLOR_DK_GREEN,Graphics.COLOR_TRANSPARENT);
		} else {
			dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_TRANSPARENT);
		}
	
	
		var xOffset = 0;
		
		if(rudderAngle < 0.0d) {
			xOffset = width/2*percentage;
		}
		
		dc.fillRectangle(width/2-xOffset, height/2-rudderHeight/2, width/2*percentage, rudderHeight);
		
		
	
	}
	
	function drawWindAngle(dc, angle) {

		// for the wind arrow to be displayed correctly we have to 
		// subtract 90 degrees as 0 is rotated to 3 o clock position 
    	var correctedAngleDegrees = Utils.radiansToDegrees(angle) - 90.0d;
    	var radians =  Utils.degreestToRadians(correctedAngleDegrees);

    	var arrowLength = 20;
    	
    	var xA = width/2 + (width/2-arrowLength) * Math.cos(radians);
		var yA = width/2 + (width/2-arrowLength) * Math.sin(radians);
		
		var xB = width/2 + (width/2+5) * Math.cos(radians+0.15d);
		var yB = width/2 + (width/2+5) * Math.sin(radians+0.15d);
		
		var xC = width/2 + (width/2+5) * Math.cos(radians-0.15d);
		var yC = width/2 + (width/2+5) * Math.sin(radians-0.15d);
		
		var pointA = [xA,yA];
    	var pointB = [xB,yB];
    	var pointC = [xC,yC];
		
		
		
		dc.fillPolygon([pointA, pointB, pointC]);

    }

}
