using Toybox.Application;
using Toybox.System;

var vessel;

class VesselConnectApp extends Application.AppBase {


    function initialize() {
        AppBase.initialize();

		vessel = new VesselModel();

    }


    
    function onStart(state) {
    
    	System.println("App Start");
    	
    	vessel.startUpdatingData();
    }

    
    function onStop(state) {
    	
		vessel.stopUpdatingData();
    	
    	System.println("App Stop");
    }

	
	function onSettingsChanged() {
		
		System.println("Settings changed");
		
		vessel.stopUpdatingData();
		vessel.configureSignalK();	
		vessel.startUpdatingData();


	}


    function getInitialView() {
    	
    	var settings = System.getDeviceSettings();
    	
    	if (!settings.phoneConnected) {
    	
      		return [ new MessageView("Phone not available",null) ];
      		
    	} else {

    		// All good

    		return [ new VesselDataView(), new VesselDataViewDelegate() ];

    	}

        
    }

}