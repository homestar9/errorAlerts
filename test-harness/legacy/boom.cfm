<cfscript>
/* This page runs outside ColdBox. Bootstrap only processes index.cfm, so
 * Application.cfc's onError() handles this page's error and reports it through
 * CaptureService.captureException().
 *
 * Add password and orderId to the query string. The alert's request collection
 * (rc) should hide the password value and show the orderId value. */
throw(
	type    = "Harness.LegacyBoom",
	message = "Error in a page outside ColdBox",
	detail  = "Thrown by /legacy/boom.cfm, which runs without ColdBox."
);
</cfscript>
