<cfscript>
/* Fails after a POST so the alert's rc section shows form fields collected
 * outside ColdBox. A GET renders a form to post from. The catalog page posts
 * its own fields; password is on the harness maskKeys list. */
if ( cgi.request_method != "POST" ) {
	writeOutput(
		"<h1>Legacy form</h1>" &
		"<form method=""post"" action=""/legacy/postForm.cfm"">" &
		"<label>Customer ID <input name=""customerId"" value=""4471""></label> " &
		"<label>Coupon <input name=""couponCode"" value=""SPRING10""></label> " &
		"<label>Password <input name=""password"" value=""hunter2""></label> " &
		"<button type=""submit"">Post and fail</button>" &
		"</form>"
	);
	abort;
}

throw(
	type    = "Harness.LegacyPostBoom",
	message = "Legacy form post failed",
	detail  = "Posted fields: #structKeyList( form )#. The rc section of the alert lists them, with any maskKeys field masked."
);
</cfscript>
