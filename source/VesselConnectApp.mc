using Toybox.Application;
using Toybox.System;

var vessel;

class VesselConnectApp extends Application.AppBase {


    function initialize() {

        AppBase.initialize();
        
        vessel = new VesselModel();

    }


    
    function onStart(state) {
    	
    	vessel.startUpdatingData();
    	
    }

    
    function onStop(state) {
    	
		vessel.stopUpdatingData();
    	
    }

	
	function onSettingsChanged() {
		
		vessel.stopUpdatingData();
		vessel.configureSignalK();	
		vessel.startUpdatingData();


	}


    function getInitialView() {
    	
    	// All good
		

    	return [ new VesselDataView(), new VesselDataViewDelegate() ];

        
    }

}