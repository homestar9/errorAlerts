<cfscript>
/* This page runs outside ColdBox, so Application.cfc's onError() reports its
 * error through CaptureService.captureException().
 *
 * It copies functions and objects into the url scope, as an application that
 * sets url.sysOut = sysOut on every request does. Before 2.9.1, Adobe's
 * serializeJSON() walked such values forever and the request never returned.
 * The alert's request collection (rc) should show [function] for each
 * function and [object ...] for the component, and arrive at once. */

/**
 * sysOut
 *
 * A page UDF the request copies into the url scope.
 *
 * @text The text to print.
 */
function sysOut( required string text ){
	writeOutput( arguments.text );
}

url.sysOut   = sysOut;
url.callback = function(){
	return "never called";
};
url.arrow   = () => "never called";
url.method  = application.cbController.getWireBox().getInstance( "OrderService" ).applyDiscount;
url.context = {
	"formatter" : function( value ){
		return arguments.value;
	},
	"service" : application.cbController.getWireBox().getInstance( "OrderService" ),
	"orderId" : "88213"
};

throw(
	type    = "Harness.LegacyFunctionInUrl",
	message = "Error in a page with functions in the url scope",
	detail  = "Thrown by /legacy/functionInUrl.cfm after it copied functions and a component into url."
);
</cfscript>
