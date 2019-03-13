using Toybox.System;
using Toybox.WatchUi;

class MessageViewDelegate extends WatchUi.BehaviorDelegate {


	function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        System.println("pressed select");

        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}