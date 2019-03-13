using Toybox.System;
using Toybox.WatchUi;

class VesselDataViewDelegate extends WatchUi.BehaviorDelegate {


	function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        System.println("pressed select");

        WatchUi.pushView(new AutopilotView(),new AutopilotDelegate(), WatchUi.SLIDE_RIGHT);
        return true;
    }
}