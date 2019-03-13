using Toybox.Application;
using Toybox.System;

var vessel;

class VesselConnectApp extends Application.AppBase {

	
	
	
    function initialize() {
        AppBase.initialize();
        
        vessel = new VesselModel("https://0.0.0.0:3443/signalk/v1/api");
        
    }

    // onStart() is called on application start up
    function onStart(state) {
    	System.println("App Start");
    	
    	
    	vessel.startUpdatingData();
    	
    	
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    	
    	vessel.stopUpdatingData();
    	
    	System.println("App Stop");
    	
    	
    }

    // Return the initial view of your application here
    function getInitialView() {
    	System.println("App get initial view");
        return [ new VesselDataView(), new VesselDataViewDelegate() ];
    }

}