using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;

class VesselDataView extends WatchUi.View {

	var width;
    var height;
    var blockHeight;

    function initialize() {
    	System.println("VesselDataView initialize");
        View.initialize();
        
        
    }

    // Update the view
    function onUpdate(dc) {

        View.onUpdate(dc);
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);
        dc.clear();
        
        width = dc.getWidth();
        height = dc.getHeight();
        blockHeight = height/3;
        

        // DRAW THE GRID
        
        dc.setPenWidth(2);
        
        dc.setColor(Graphics.COLOR_ORANGE,Graphics.COLOR_TRANSPARENT);
        
        dc.drawLine(0, blockHeight, width, blockHeight);
        dc.drawLine(0, blockHeight * 2, width, blockHeight * 2);
        dc.drawLine(width/2, blockHeight, width/2, blockHeight * 2);
        
        // DRAW THE ARCS
        
        var arcLineWidth = 10;
        dc.setPenWidth(arcLineWidth);
        
        
        
        // Stareboard 
        dc.setColor(Graphics.COLOR_DK_GREEN,Graphics.COLOR_TRANSPARENT);
        dc.drawArc(width/2, height/2,(width/2), Graphics.ARC_CLOCKWISE, 90, 30);
        
        // Port 
        dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_TRANSPARENT);
        dc.drawArc(width/2, height/2,(width/2), Graphics.ARC_COUNTER_CLOCKWISE, 90, 150);
       
        
        // DRAW SHIP DATA
        
        // Speed over ground
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_TRANSPARENT);
            
        drawDataText(dc,width/2,10,"SOG",vessel.getSpeedOverGroundKnotsString());
        
        drawDataText(dc,width/2,height-blockHeight,"DBT",vessel.getDepthBelowTranscuderMeterString());
        
        drawDataText(dc,(width/4),blockHeight+5,"AWA",vessel.getAppearantWindAngleDegreeString());
        
        drawDataText(dc,(width*0.75),blockHeight+5,"AWS",vessel.getApparentWindSpeedKnotsString());
        
        
        drawWindAngle(dc,vessel.apparentWindAngle);
        
        
        

    }
    
    function drawDataText(dc,x,y,labelText,valueText) {
    
    	dc.drawText(
        x,                     
        y+4,                   
        Graphics.FONT_SYSTEM_XTINY,     
        labelText,                   
        Graphics.TEXT_JUSTIFY_CENTER);
        
        dc.drawText(
        x,                      
        y+26,                     
        Graphics.FONT_SYSTEM_LARGE,       
        valueText,                         
        Graphics.TEXT_JUSTIFY_CENTER);
    
    }
    
    function drawWindAngle(dc, angle) {

		// for the wind arrow to be displayed correctly we have to 
		// subtract 90 degrees as 0 is rotated to 3 o clock position 
    	var correctedAngleDegrees = vessel.radiansToDegrees(angle) - 90.0d;
    	var radians =  vessel.degreestToRadians(correctedAngleDegrees);

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
		
		
		dc.setColor(Graphics.COLOR_ORANGE,Graphics.COLOR_TRANSPARENT);
		dc.fillPolygon([pointA, pointB, pointC]);

    }

}
