using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;

using Utilities as Utils;

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
        

		if(vessel.errorCode == null) {
		
			drawValues(dc);
		
		}else {
		
			drawError(dc);
		
		}
        
        

    }
    
    function drawError(dc) {
    
    	// DRAW THE GRID
        
        var errorMessage = Utils.errorMessage(vessel.errorCode);
        
        dc.setPenWidth(2);
        
        dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_WHITE);
        
        dc.drawLine(0, blockHeight, width, blockHeight);
        dc.drawLine(0, blockHeight * 2, width, blockHeight * 2);
        
        
        if(!vessel.credentialsAvailable || vessel.errorCode == 401) {
        	errorMessage = "INVALID OR\nMISSING CREDENTIALS";
        }else {
        	//drawDataText(dc,width/2,10,"ERROR",vessel.errorCode);
        }
        
        
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);
        
        dc.drawText(
      	width/2,                     
      	height/2,                   
      	Graphics.FONT_SYSTEM_TINY,     
      	errorMessage,                   
      	(Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
        
    
    }
    

    
    function drawValues(dc) {
    
    	// DRAW THE GRID
        
        dc.setPenWidth(2);
        
        dc.setColor(Graphics.COLOR_ORANGE,Graphics.COLOR_WHITE);
        
        dc.drawLine(0, blockHeight, width, blockHeight);
        dc.drawLine(0, blockHeight * 2, width, blockHeight * 2);
        dc.drawLine(width/2, blockHeight, width/2, blockHeight * 2);
        
        // DRAW THE ARCS
        
        var arcLineWidth = 15;
        dc.setPenWidth(arcLineWidth);
        
        // Stareboard 
        dc.setColor(Graphics.COLOR_DK_GREEN,Graphics.COLOR_WHITE);
        dc.drawArc(width/2, height/2,(width/2), Graphics.ARC_CLOCKWISE, 90, 45);
        
        // Port 
        dc.setColor(Graphics.COLOR_DK_RED,Graphics.COLOR_WHITE);
        dc.drawArc(width/2, height/2,(width/2), Graphics.ARC_COUNTER_CLOCKWISE, 90, 135);
       
        
        // DRAW SHIP DATA
        
        // Speed over ground
        
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_WHITE);
            
        drawDataText(dc,width/2,10,"SOG",vessel.getSpeedOverGroundKnotsString());
        drawDataText(dc,width/2,height-blockHeight,"DBT",vessel.getDepthBelowTranscuderMeterString());
        drawDataText(dc,(width/4),blockHeight+5,"AWA",vessel.getAppearantWindAngleDegreeString());
        drawDataText(dc,(width*0.75),blockHeight+5,"AWS",vessel.getApparentWindSpeedKnotsString());
        
        Utils.drawWindAngle(dc,vessel.apparentWindAngle, width);
    
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
    


}

class VesselDataViewDelegate extends WatchUi.BehaviorDelegate {


	function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {

		if(vessel.errorCode != null) {
			return true;
		}

        WatchUi.pushView(new AutopilotView(),new AutopilotDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }
}
