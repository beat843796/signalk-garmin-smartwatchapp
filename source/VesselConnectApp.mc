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
    	
    	// All good
			vessel.startUpdatingData();

    		return [ new VesselDataView(), new VesselDataViewDelegate() ];

        
    }

}