<cfscript>
/* Throw an error after a POST to show form fields in the alert's request
 * collection (rc), even though this page runs outside ColdBox. A GET shows
 * a form to submit. The scenario list submits its own fields. The harness
 * includes password in maskKeys, so the alert hides that field's value. */
if ( cgi.request_method != "POST" ) {
	writeOutput(
		"<h1>Legacy form</h1>" &
		"<form method=""post"" action=""/legacy/postForm.cfm"">" &
		"<label>Customer ID <input name=""customerId"" value=""4471""></label> " &
		"<label>Coupon <input name=""couponCode"" value=""SPRING10""></label> " &
		"<label>Password <input name=""password"" value=""hunter2""></label> " &
		"<button type=""submit"">Submit form and trigger an error</button>" &
		"</form>"
	);
	abort;
}

throw(
	type    = "Harness.LegacyPostBoom",
	message = "Legacy form post failed",
	detail  = "Posted fields: #structKeyList( form )#. The alert's request collection (rc) lists these fields. Values are hidden for keys in maskKeys."
);
</cfscript>
