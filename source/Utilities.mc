using Toybox.Math;
using Toybox.Graphics;

module Utilities {


	const FACTOR_MS_TO_KNOTS = 1.943844d;
	
	function meterPerSecondToKnots(metersPerSecond) {
	
		var knots = metersPerSecond * FACTOR_MS_TO_KNOTS;
		
		return knots;
	
	}

	function degreestToRadians(degrees) {
	
		var radians = degrees * Math.PI / 180.0d;
		
		return radians;
	
	}
	
	function metersToNauticalMiles(meters) {
	
		var nm = meters * 0.00053995680d;
		
		return nm;
	
	}
	
	function radiansToDegrees(radians) {
		
		var degrees = radians * 180.0d / Math.PI;
		
		return degrees;
	
	}
	
	function kelvinToCelsius(kelvin) {
		
		var celsius = kelvin - 273.15d;
		
		return celsius;
	
	}
	
	function drawWindAngle(dc, angle, width) {

		// for the wind arrow to be displayed correctly we have to 
		// subtract 90 degrees as 0 is rotated to 3 o clock position 
    	var correctedAngleDegrees = radiansToDegrees(angle) - 90.0d;
    	var radians =  degreestToRadians(correctedAngleDegrees);

    	var arrowLength = 20;
    	
    	var xA = width/2 + (width/2-arrowLength) * Math.cos(radians);
		var yA = width/2 + (width/2-arrowLength) * Math.sin(radians);
		
		var xB = width/2 + (width/2+5) * Math.cos(radians+0.15d);
		var yB = width/2 + (width/2+5) * Math.sin(radians+0.15d);
		
		var xC = width/2 + (width/2+5) * Math.cos(radians-0.15d);
		var yC = width/2 + (width/2+5) * Math.sin(radians-0.15d);
		
		var pointA = [xA,yA];
    	var pointB = [xB,yB];
    	var pointC = [xC,yC];
		
		
		dc.setColor(Graphics.COLOR_ORANGE,Graphics.COLOR_WHITE);
		dc.fillPolygon([pointA, pointB, pointC]);

    }
    
    var errorList = [
  { :msg => "UNKNOWN ERROR", :code => 0 },
  { :msg => "BLE ERROR", :code => -1 },
  { :msg => "BLE HOST\nTIMEOUT", :code => -2 },
  { :msg => "BLE SERVER\nTIMEOUT", :code => -3 },
  { :msg => "BLE NO DATA", :code => -4 },
  { :msg => "BLE REQUEST\nCANCELLED", :code => -5 },
  { :msg => "BLE QUEUE\nFULL", :code => -101 },
  { :msg => "BLE REQUEST\nTOO LARGE", :code => -102 },
  { :msg => "BLE UNKNOWN\nSEND ERROR", :code => -103 },
  { :msg => "PHONE CONNECTION\nUNAVAILABLE", :code => -104 },
  { :msg => "INVALID HTTP\nHEADER FIELDS\nIN REQUEST", :code => -200 },
  { :msg => "INVALID HTTP\nBODY IN REQUEST", :code => -201 },
  { :msg => "INVALID HTTP\nMETHOD IN REQUEST", :code => -202 },
  { :msg => "NETWORK REQUEST\nTIMED OUT", :code => -300 },
  { :msg => "INVALID HTTP\nBODY IN\nNETWORK RESPONSE", :code => -400 },
  { :msg => "INVALID HTTP\nHEADER FIELDS\nIN NETWORK RESPONSE", :code => -401 },
  { :msg => "NETWORK RESPONSE\nTOO LARGE", :code => -402 },
  { :msg => "NETWORK RESPONSE\nOUT OF MEMORY", :code => -403 },

{ :msg => "Continue", :code => 100 },
{ :msg => "Switching Protocol", :code => 101 },
{ :msg => "OK", :code => 200 },
{ :msg => "Created", :code => 201 },
{ :msg => "Accepted", :code => 202 },
{ :msg => "Non-Authoritative\nInformation", :code => 203 },
{ :msg => "No Content", :code => 204 },
{ :msg => "Reset Content", :code => 205 },
{ :msg => "Partial Content", :code => 206 },
{ :msg => "Multiple Choices", :code => 300 },
{ :msg => "Moved Permanently", :code => 301 },
{ :msg => "Found", :code => 302 },
{ :msg => "See Other", :code => 303 },
{ :msg => "Not Modified", :code => 304 },
{ :msg => "Temporary\nRedirect", :code => 307 },
{ :msg => "Permanent\nRedirect", :code => 308 },
{ :msg => "Bad Request", :code => 400 },
{ :msg => "Unauthorized", :code => 401 },
{ :msg => "Forbidden", :code => 403 },
{ :msg => "SignalK Server\nNot\nFound", :code => 404 },
{ :msg => "Method\nNot Allowed", :code => 405 },
{ :msg => "Not Acceptable", :code => 406 },
{ :msg => "Proxy Authentication\nRequired", :code => 407 },
{ :msg => "Request Timeout", :code => 408 },
{ :msg => "Conflict", :code => 409 },
{ :msg => "Gone", :code => 410 },
{ :msg => "Length Required", :code => 411 },
{ :msg => "Precondition\nFailed", :code => 412 },
{ :msg => "Payload\nToo Large", :code => 413 },
{ :msg => "URI Too Long", :code => 414 },
{ :msg => "Unsupported\nMedia Type", :code => 415 },
{ :msg => "Range Not\nSatisfiable", :code => 416 },
{ :msg => "Expectation Failed", :code => 417 },
{ :msg => "Upgrade\nRequired", :code => 426 },
{ :msg => "Precondition\nRequired", :code => 428 },
{ :msg => "Too Many\nRequests", :code => 429 },
{ :msg => "Request Header\nFields Too Large", :code => 431 },
{ :msg => "Unavailable For\nLegal Reasons", :code => 451 },
{ :msg => "Internal\nServer Error", :code => 500 },
{ :msg => "Not Implemented", :code => 501 },
{ :msg => "Bad Gateway", :code => 502 },
{ :msg => "SignalK Service\nUnavailable", :code => 503 },
{ :msg => "Gateway Timeout", :code => 504 },
{ :msg => "HTTP Version\nNot Supported", :code => 505 },
{ :msg => "Network\nAuthentication Required", :code => 511 }
];

	function errorMessage(code) {
  		var result = code;
  		
  		for( var i = 0; i < errorList.size(); i++ ) {
  		
    		if( errorList[i][:code] == code) {
    		
      			result = errorList[i][:msg];
      			break;
      			
    		}
    		
  		}
  		return result;
}


}
	
