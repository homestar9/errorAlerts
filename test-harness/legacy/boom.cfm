<cfscript>
/* A plain page outside ColdBox. Bootstrap only processes index.cfm, so this
 * file runs as ordinary CFML and its exception reaches Application.cfc
 * onError(), which passes it to CaptureService.captureException().
 *
 * Request it with a password and an orderId in the query string to see the url scope in the
 * alert's rc section with password masked and orderId readable. */
throw(
	type    = "Harness.LegacyBoom",
	message = "Legacy page explosion",
	detail  = "Thrown by /legacy/boom.cfm, which never enters ColdBox."
);
</cfscript>
