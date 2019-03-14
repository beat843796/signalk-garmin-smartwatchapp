using Toybox.Application;
using Toybox.System;

var vessel;

class VesselConnectApp extends Application.AppBase {

	
	var baseURL;
	var username;
	var password;

	
    function initialize() {
        AppBase.initialize();

		vessel = new VesselModel();

    }

	function readSettings() {
	
		baseURL = Application.Properties.getValue("baseurl_prop");
        username = Application.Properties.getValue("username_prop");
        password = Application.Properties.getValue("password_prop");
        
        System.println("Settings: " + baseURL + " " + username + " " + password);
	
	}
	
	function credentialsFound() {
	
		if(baseURL == null || username == null || password == null) {
		
			System.println("Missing credentails");
			return false;
		
		}else {
		
			return true;
		
		}
	
	}

    // onStart() is called on application start up
    function onStart(state) {
    	System.println("App Start");
		readSettings();
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    	
		vessel.stopUpdatingData();
    	
    	System.println("App Stop");
    	
    	
    }

	
	function onSettingsChanged() {
		
		System.println("Settings changed");
		
		vessel.stopUpdatingData();
		
		readSettings();
		
		startSignalK();

	}

	function startSignalK() {

		vessel.configureSignalK(baseURL,username,password);	
		vessel.startUpdatingData();
	
	}

    // Return the initial view of your application here
    function getInitialView() {

		System.println("View");
    	
    	var settings = System.getDeviceSettings();
    	if (!settings.phoneConnected) {
    	
      		return [ new MessageView("Phone not available",null) ];
      		
    	} else {
    	
    		if(credentialsFound()) {
    	
    			// All good
    	
    			startSignalK();

    			return [ new VesselDataView(), new VesselDataViewDelegate() ];
    			
    		}else {
    	
    			var messageView = new MessageView("Setup in GCM needed",null);
            	return [ messageView ];

    		}
    	}

        
    }

}