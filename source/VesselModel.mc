using Toybox.System;
using Toybox.Application;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Math;

enum {
   
   AP_STATE_STANDBY = 0,
   AP_STATE_AUTO = 1,
   AP_STATE_WIND = 2,
   AP_STATE_TRACK = 3,
   AP_STATE_NOT_SUPPORTED = 4,
   
}

class VesselModel {

	const FACTOR_MS_TO_KNOTS = 1.943844d;

	protected var baseURL = null;
	protected var updateTimer;

	//Strings
    public var speedOverGround;				// meter/second
    public var apparentWindSpeed;			// meter/second
    public var trueWindSpeed;				// meter/second
    public var depthBelowTranscuder;		// meter
    public var apparentWindAngle;			// radians
    public var courseOverGround;			// radians
    public var heading;						// radians
    public var rudderAngle;					// radians
    
    public var targetHeadingTrue;			// radians
    public var targetHeadingMagnetic;		// radians
    public var targetHeadingWindAppearant;	// radians
    
    public var autopilotState = "---";
    
    function initialize(signalKBaseURL) {
        
        baseURL = signalKBaseURL;
    	System.println("SignalK Base URL is: " + baseURL);
    	
    	resetVesselData();
        
    }
    
    function startUpdatingData() {
    	System.println("Start updating data");

        makeRequest();
    }
    
    function stopUpdatingData() {
    	System.println("Stopping updating data");

        invalidateTimer(updateTimer);
    }
    
    // In case invalid date is received, invalidate all values
    function resetVesselData() {
    
    	speedOverGround = 0.0d;		
    	apparentWindSpeed = 0.0d;	
    	trueWindSpeed = 0.0d;		
    	depthBelowTranscuder = 0.0d;
    	apparentWindAngle = 0.0d;
    	courseOverGround = 0.0d;
    	heading = 0.0d;
    	rudderAngle = 0.0d;
    	targetHeadingTrue = 0.0d;
    	targetHeadingMagnetic = 0.0d;
    	targetHeadingWindAppearant = 0.0d;
    	
    	autopilotState = "---";
        
    }
    
    function getSpeedOverGroundKnotsString() {

    	return meterPerSecondToKnots(speedOverGround).format("%.1f");
    	
    }
    
    function getApparentWindSpeedKnotsString() {

    	return meterPerSecondToKnots(apparentWindSpeed).format("%.1f");
    }
    
    function getTrueWindSpeedKnotsString() {

    	return meterPerSecondToKnots(trueWindSpeed).format("%.1f");
    	
    }
    
    function getDepthBelowTranscuderMeterString() {

    	return depthBelowTranscuder.format("%.1f") + "m";
    	
    }
    
    function getAppearantWindAngleDegreeString() {

		var degrees = radiansToDegrees(apparentWindAngle).abs();
		
    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getCourseOverGroundDegreeString() {

		var degrees = radiansToDegrees(courseOverGround).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getHeadingDegreeString() {

		var degrees = radiansToDegrees(heading).abs();

    	return degrees.format("%.0f") + "°";
    	
    }

    function getTargetHeadingTrueDegreeString() {

		var degrees = radiansToDegrees(targetHeadingTrue).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getTargetHeadingMagneticDegreeString() {

		var degrees = radiansToDegrees(targetHeadingMagnetic).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getTargetHeadingWindAppearantDegreeString() {

		var degrees = radiansToDegrees(targetHeadingWindAppearant).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function autoPilotPlusOne() {
    	System.println("AP +1");
    }
    
    function autoPilotMinusOne() {
    	System.println("AP -1");
    }
    
    function autoPilotPlusTen() {
    	System.println("AP +10");
    }
    
    function autoPilotMinusTen() {
    	System.println("AP -10");
    }
    
  
    function setAutopilotState(apMode) {
    	System.println("Selected ap mode: " + apMode);
    } 

	function meterPerSecondToKnots(metersPerSecond) {
	
		var knots = metersPerSecond * FACTOR_MS_TO_KNOTS;
		
		return knots;
	}

	function degreestToRadians(degrees) {
	
		var radians = degrees * Math.PI / 180.0d;
		
		return radians;
	
	}
	
	function radiansToDegrees(radians) {
		
		var degrees = radians * 180.0d / Math.PI;
		
		return degrees;
	}
	
    
    
    function invalidateTimer(timer) {
    
    	if(timer == null) {
    		return;
    	}
    
    	timer.stop();
        timer = null;
    
    }
    
    
    function makeRequest() {

       invalidateTimer(updateTimer);
       System.println("make web request");
        Communications.makeWebRequest(
            baseURL + "/vessels/self",
            {
            },
            {
              :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {                                           
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED
                },
                 :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON 
             
            },
            method(:onReceive)
        );
    }
    

    function onReceive(responseCode, data) {
        
        System.println("response code " + responseCode);

        if (responseCode == 200) {
        	// Parse JSON data
        	
        	try {
  				apparentWindAngle = data["environment"]["wind"]["angleApparent"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				depthBelowTranscuder = data["environment"]["depth"]["belowTransducer"]["value"].toFloat();
			}
			catch (ex) {}

			try {
  				trueWindSpeed = data["environment"]["wind"]["speedTrue"]["value"].toFloat();
			}
			catch (ex) {}

			try {
  				apparentWindSpeed = data["environment"]["wind"]["speedApparent"]["value"].toFloat();
			}
			catch (ex) {}

			try {
  				speedOverGround = data["navigation"]["speedOverGround"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				courseOverGround = data["navigation"]["courseOverGroundTrue"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				heading = data["navigation"]["headingTrue"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				rudderAngle = data["steering"]["rudderAngle"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				autopilotState = data["steering"]["autopilot"]["state"]["value"];
			}
			catch (ex) {}
			
			try {
  				targetHeadingMagnetic = data["steering"]["autopilot"]["target"]["headingMagnetic"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				targetHeadingTrue = data["steering"]["autopilot"]["target"]["headingTrue"]["value"].toFloat();
			}
			catch (ex) {}
			
			try {
  				targetHeadingWindAppearant = data["steering"]["autopilot"]["target"]["windAngleApparent"]["value"].toFloat();
			}
			catch (ex) {}

        	
        	updateTimer = new Timer.Timer();
        	updateTimer.start(method(:makeRequest), 1000, false);
        
        
        	WatchUi.requestUpdate();
        	
        	
        } else {
	        System.println("Response Code: " + responseCode);
            resetVesselData();
        }
        
        data = null;
        
        logState();

    }
    
    
    function getNameForActiveState() {
   
   		var stateName = autopilotState.toUpper();
   		
   		if(stateName.equals("ROUTE")) {
   			stateName = "TRACK";
   		}
   
   		return stateName;
   
    }
    
    function logState() {
    	System.println("SOG: " + speedOverGround + 
        "\nAWS: " + apparentWindSpeed + 
        "\nTWS: " + trueWindSpeed + 
        "\nDBT: " + depthBelowTranscuder  +
        "\nAWA: " + apparentWindAngle +
        "\nCOG: " + courseOverGround +
        "\nHDG: " + heading +
        "\nTARGET_HDG_MAG: " + targetHeadingMagnetic + 
        "\nTARGET_HDG_TRUE: " + targetHeadingTrue + 
        "\nTARGET_AWA: " + targetHeadingWindAppearant + 
        "\nRudder: " + rudderAngle + 
        "\nAUTOPILOT: " + autopilotState + "\n---------------\n");
    }


}