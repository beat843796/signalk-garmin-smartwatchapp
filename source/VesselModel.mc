using Toybox.System;
using Toybox.Application;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Attention;

using Toybox.Application.Storage;

using Utilities as Utils;

enum {
   
   AP_STATE_STANDBY = 0,
   AP_STATE_AUTO = 1,
   AP_STATE_WIND = 2,
   AP_STATE_TRACK = 3,
   AP_STATE_NOT_SUPPORTED = 4,
   
}

class VesselModel {

	const updateInterval = 50;
	const retryInterval = 3000;	
	
	const tokenKey = "signalk-token";

	protected var baseURL = null;
	protected var username = null;
	protected var password = null;
	protected var token = null;
	
	protected var updateTimer;
	protected var retryTimer;

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
    
    private var isAutopilotRequestPending = false;
    
    // Failure indication
    public var credentialsAvailable = false;
    public var errorCode = null;
    
	
    
    function initialize() {

        configureSignalK();

    }
    
 	function configureSignalK() {
 	
 		baseURL = "https://seatalk.defectradar.com"; //Application.Properties.getValue("baseurl_prop"); // seatalk.defectradar.com
        username = "garmin"; //Application.Properties.getValue("username_prop");
        password = "garmin123"; //Application.Properties.getValue("password_prop");
        
        token = Storage.getValue(tokenKey);

        if(baseURL == null || username == null || password == null) {
		
			System.println("Missing credentails");
			credentialsAvailable = false;
		
		}else {
		
			credentialsAvailable = true;
		
		}
        
        
        
        resetVesselData();
 	
 	}
    
    function startUpdatingData() {

		if(token != null) {
		
			updateVesselDataFromServer();
			
		} else {
		
			loginToSignalKServer();
			
		}

        
        
    }
    
    
    
    function stopUpdatingData() {

		Communications.cancelAllRequests();
        invalidateTimer(updateTimer);
        invalidateTimer(retryTimer);
        
    }
    
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

    	return Utils.meterPerSecondToKnots(speedOverGround).format("%.1f");
    	
    }
    
    function getApparentWindSpeedKnotsString() {

    	return Utils.meterPerSecondToKnots(apparentWindSpeed).format("%.1f");
    }
    
    function getTrueWindSpeedKnotsString() {

    	return Utils.meterPerSecondToKnots(trueWindSpeed).format("%.1f");
    	
    }
    
    function getDepthBelowTranscuderMeterString() {

    	return depthBelowTranscuder.format("%.1f") + "m";
    	
    }
    
    function getAppearantWindAngleDegreeString() {

		var degrees = Utils.radiansToDegrees(apparentWindAngle).abs();
		
    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getCourseOverGroundDegreeString() {

		var degrees = Utils.radiansToDegrees(courseOverGround).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getHeadingDegreeString() {

		var degrees = Utils.radiansToDegrees(heading).abs();

    	return degrees.format("%.0f") + "°";
    	
    }

    function getTargetHeadingTrueDegreeString() {

		var degrees = Utils.radiansToDegrees(targetHeadingTrue).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getTargetHeadingMagneticDegreeString() {

		var degrees = Utils.radiansToDegrees(targetHeadingMagnetic).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getTargetHeadingWindAppearantDegreeString() {

		var degrees = Utils.radiansToDegrees(targetHeadingWindAppearant).abs();

    	return degrees.format("%.0f") + "°";
    	
    }
    
    function getNameForActiveState() {
   
   		var stateName = autopilotState.toUpper();
   		
   		if(stateName.equals("ROUTE")) {
   			stateName = "TRACK";
   		}
   
   		return stateName;
   
    }
        
  
    function setAutopilotState(state) {
    	
    	var command = { "action" => "setState", "value" => state };
		
		sendAutopilotCommand(command);
    } 

	function changeHeading(change) {
	
		var command = { "action" => "changeHeading", "value" => change };
		
		sendAutopilotCommand(command);

	}

    function invalidateTimer(timer) {
    
    	if(timer == null) {
    		return;
    	}
    
    	timer.stop();
        timer = null;
    
    }
    
    ////////////////////////////////////////////////////////
    ///////////////////// NETWORKING ///////////////////////
    ////////////////////////////////////////////////////////
    
    function loginToSignalKServer() {
		
		token = null;
		Storage.setValue(tokenKey,null);

        Communications.makeWebRequest(
            baseURL + "/signalk/v1/auth/login",
            {
            	"username" => username,
              	"password" => password
            },
            {
              	:method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {                                          
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON 
             
            },
            method(:onLoginReceive)
        );
    
    }
    
    function onLoginReceive(responseCode, data) {
    
    	if(responseCode == 200) {
    	
    		token = "JWT " + data["token"];
    		
    		Storage.setValue(tokenKey,token);
    		
    		updateVesselDataFromServer();
    		
    		errorCode = null;
    		
    		
    	}else {
   
   			System.println("Login failed: " + responseCode);
   
    		showNetworkError(responseCode);
    		
    		startRetryTimer();
    		
    	}

    }
    
    function updateVesselDataFromServer() {
       
       invalidateTimer(updateTimer);

       Communications.makeWebRequest(
            baseURL + "/plugins/minimumvesseldatarest/vesseldata",
            {
            },
            {
            	:method => Communications.HTTP_REQUEST_METHOD_GET,
              	:headers => {                                         
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED,
                    "Authorization" => token
                },
             	:responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
             
            },
            method(:onReceive)
        );
    }
    

    function onReceive(responseCode, data) {
 

        if (responseCode == 200) {

        	try {

				// FLOAT VALUES

				depthBelowTranscuder = setValueIfPresent(data["depthBelowTransducer"]);
				trueWindSpeed = setValueIfPresent(data["windSpeedTrue"]);
				apparentWindSpeed = setValueIfPresent(data["windSpeedApparent"]);
				speedOverGround = setValueIfPresent(data["speedOverGround"]);
				courseOverGround = setValueIfPresent(data["courseOverGroundTrue"]);
				apparentWindAngle = setValueIfPresent(data["headingTrue"]);
				rudderAngle = setValueIfPresent(data["rudderAngle"]);
				targetHeadingMagnetic = setValueIfPresent(data["autopilotTargetHeadingMagnetic"]);
				targetHeadingTrue = setValueIfPresent(data["autopilotTargetHeadingTrue"]);
				targetHeadingWindAppearant = setValueIfPresent(data["autopilotTargetWindAngleApparent"]);

				// STRING VALUES
				
				if(data["autopilotState"] != null) {
					autopilotState = data["autopilotState"];
				}else {
					autopilotState = "---";
				}
				
			}
			catch (ex) {
			
				ex.printStackTrace();
				resetVesselData();
			
			}

			errorCode = null;

			WatchUi.requestUpdate();

        	updateTimer = new Timer.Timer();
        	updateTimer.start(method(:updateVesselDataFromServer), updateInterval, false);
        
        	//logState();
        
        	
        } else {
        
        	System.println("Response Code: " + responseCode);
        
        	if(responseCode == 401 || responseCode == -400) {
        	
        		loginToSignalKServer();
        	
        	}else {
        	
        	
            resetVesselData();

            showNetworkError(responseCode);
            
            startRetryTimer();
        	
        	}

        }
        
        
        data = null;

    }
    
    function sendAutopilotCommand(command) {
    	
    	
    	
    	if(isAutopilotRequestPending == true) {
    		
    		return;
    	
    	}
    	
    	isAutopilotRequestPending = true;
    	
		Communications.makeWebRequest(
            baseURL + "/plugins/raymarineautopilotfork/command",
            command,
            {
              	:method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {    
                	"Accept" => "application/json",                                      
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED,
                    "Authorization" => token
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                
             
            },
            method(:onAutopilotReceive)
        );


    
    }
    
    function onAutopilotReceive(responseCode, data) {

		
    	if(responseCode == 200) {
    		
    		Attention.playTone(Attention.TONE_KEY);
    		
    		
			}else {
				if (Attention has :vibrate) {
    			var vibeData =
    				[
       				 new Attention.VibeProfile(50, 100), // On for 200 ms
       				];
       				
       			Attention.vibrate(vibeData);
			}
			
    	} 
    	
    	
    	isAutopilotRequestPending = false;
    	

    }
    
    function setValueIfPresent(value) {
    
    	if(value != null) {
    	
    		return value;
    	
    	}else {
    		return 0.0;
    	} 
    
    }
    
    function showNetworkError(responseCode) {
    	
    	errorCode = responseCode;     
                
        WatchUi.requestUpdate();
    }
    
    function startRetryTimer() {
    
    	System.println("Receivend Networking error. Retry in " + retryInterval / 1000 + " seconds");
    
    	retryTimer = new Timer.Timer();
        retryTimer.start(method(:startUpdatingData), retryInterval, false);
    
    }

    ////////////////////////////////////////////////////////
    ///////////////////// LOGGING //////////////////////////
    ////////////////////////////////////////////////////////
    
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