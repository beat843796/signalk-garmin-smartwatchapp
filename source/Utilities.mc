using Toybox.Math;

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
	
	function radiansToDegrees(radians) {
		
		var degrees = radians * 180.0d / Math.PI;
		
		return degrees;
	
	}


}
	
