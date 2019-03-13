using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

class MessageView extends Ui.View {

    var message;
	var errorCode;
    function initialize(msg, error) {
      View.initialize();
      
      message = msg;
        
      if(message.length() > 20) {
      	message = message.substring(0,20) + "...";
      }
      
      errorCode = error;
    }


    // Update the view
    function onUpdate(dc) {
      View.onUpdate(dc);
       
        
      dc.setColor(Graphics.COLOR_WHITE,Graphics.COLOR_BLACK);
      dc.clear();
        
      var width = dc.getWidth();
      var height = dc.getHeight();
      
      dc.drawText(
      width/2,                     
      height/2,                   
      Graphics.FONT_SYSTEM_TINY,     
      message,                   
      (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
        
        
        
      if(errorCode != null) {
      	dc.drawText(
        width/2,                     
        height/2/2,                   
        Graphics.FONT_NUMBER_MEDIUM,     
        errorCode,                   
        (Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
      }
        
    }

}
