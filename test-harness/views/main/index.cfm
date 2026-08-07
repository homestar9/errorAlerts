<cfscript>
	/* Every scenario in one place. The table below and the "fire all" button both
	 * read this, so adding a scenario means adding one row here plus the matching
	 * action in handlers/Trigger.cfc.
	 *
	 * method  - "POST" sends a form post instead of a GET.
	 * alerts  - true when an email is expected, false when one would be a bug.
	 * skipAll - leave the scenario out of the "fire all" sweep. */
	groups = [
		{
			title       : "Unhandled exceptions",
			description : "These reach the module through its onException interceptor, because this harness sets a custom exceptionHandler. Category: UnhandledException.",
			scenarios   : [
				{ route : "/trigger/handlerThrow", note : "Plain throw() in a handler action. Short stack." },
				{ route : "/trigger/modelThrow", note : "Fails two components deep, in PaymentGateway." },
				{ route : "/trigger/deepStack", note : "Fails 25 frames down. The email should list only 10." },
				{ route : "/trigger/undefinedVariable", note : "Reads a variable that was never set." },
				{ route : "/trigger/typeMismatch", note : "Passes text to a numeric argument." },
				{ route : "/trigger/divideByZero", note : "Divide by zero inside a model." },
				{ route : "/trigger/missingMethod", note : "Calls a method the component does not have." },
				{ route : "/trigger/arrayIndex", note : "Reads position 99 of a two-item array." },
				{ route : "/trigger/nullReference", note : "Calls a method on a lookup that returned nothing." },
				{ route : "/trigger/viewError", note : "A view throws part-way through rendering." },
				{ route : "/trigger/layoutError", note : "The view renders, then the layout throws." },
				{ route : "/trigger/interceptorThrow", note : "HarnessFailure throws at preEvent, before any action runs." },
				{ route : "/trigger/wireboxThrow", note : "A component whose init() throws, so WireBox fails." },
				{ route : "/trigger/customType", note : "Type Harness.Custom.PaymentDeclined. Add it to ignoreExceptionTypes to silence it." },
				{ route : "/trigger/wrappedCause", note : "Throws with another exception as its cause." },
				{ route : "/trigger/fileNotFound", note : "Reads a file that is not there." },
				{ route : "/trigger/httpFailure", note : "cfhttp to a closed port with throwOnError." },
				{ route : "/trigger/timeoutError", note : "The shape of a slow-dependency timeout." },
				{ route : "/trigger/noSuchAction", note : "Real handler, action that was never written." },
				{ route : "/trigger/invalidEvent", note : "Handler that does not exist at all." },
				{ route : "/api/boom", note : "Throws inside a RestHandler, which logs and announces the same exception. One email." },
				{ route : "/apiFault/boom", note : "Throws in a RestHandler preHandler, which reaches onError(). That log is the only report, so it still alerts." },
				{ route : "/api/logged", note : "A RestHandler that catches and logs its own failure." }
			]
		},
		{
			title       : "Database query failures",
			description : "The first six need an in-memory database. The last two work on any engine.",
			scenarios   : [
				{ route : "/trigger/dbSyntax", note : "SQL the database cannot parse." },
				{ route : "/trigger/dbMissingTable", note : "Selects from a table that does not exist." },
				{ route : "/trigger/dbMissingColumn", note : "Selects a column the table does not have." },
				{ route : "/trigger/dbConstraint", note : "Inserts a duplicate primary key." },
				{ route : "/trigger/dbInTransaction", note : "Second insert fails inside a transaction, so the first rolls back." },
				{ route : "/trigger/dbBadParam", note : "Binds text to an integer query parameter." },
				{ route : "/trigger/dbNoDatasource", note : "Datasource name that was never declared. Works everywhere." },
				{ route : "/trigger/dbDeadHost", note : "Datasource pointed at a closed port. Takes a few seconds." }
			]
		},
		{
			title       : "Manual LogBox messages",
			description : "These reach the module through its LogBox appender on the root logger.",
			scenarios   : [
				{ route : "/trigger/logError", note : "log.error() with no exception. The email has no Exception section." },
				{ route : "/trigger/logErrorWithException", note : "Caught exception passed as extraInfo." },
				{ route : "/trigger/logErrorWithData", note : "A plain struct as extraInfo, which fills the Extra info section." },
				{ route : "/trigger/logFatal", note : "FATAL severity." },
				{ route : "/trigger/logWarn", note : "Below levelMin. No email should arrive.", alerts : false },
				{ route : "/trigger/logInfo", note : "Below levelMin. No email should arrive.", alerts : false },
				{ route : "/trigger/logIgnoredCategory", note : "Category starts with cbmailservices. No email should arrive.", alerts : false },
				{ route : "/trigger/logFromThread", note : "Logged from a thread, so there is no request context." }
			]
		},
		{
			title       : "Throttling and digests",
			description : "Throttle settings are shortened while ERRORALERTS_MAILER is smtp, so a digest lands about a minute after a burst.",
			scenarios   : [
				{ route : "/trigger/burst", note : "Same error 10 times. Expect 3 emails, then a digest for the other 7." },
				{ route : "/trigger/burstVariants", note : "10 errors differing only by numbers and UUIDs. Should collapse to one signature." },
				{ route : "/trigger/burstDistinct", note : "5 different errors. Expect 5 emails." },
				{ route : "/trigger/flushDigest", note : "Sends the digest now instead of waiting for the scheduler.", skipAll : true },
				{ route : "/trigger/throttleStatus", note : "Prints the current settings. Sends nothing.", alerts : false, skipAll : true },
				{ route : "/trigger/reset", note : "Clears throttle windows and the in-memory mailbox.", alerts : false, skipAll : true }
			]
		},
		{
			title       : "Email content checks",
			description : "These exist to be read, not just counted. Open each email and check the section named in the note.",
			scenarios   : [
				{ route : "/trigger/maskedRc?password=hunter2&api_key=sk-live-abc&token=xyz&orderId=88213", note : "Secrets in rc should read *** masked ***. orderId should stay readable." },
				{ route : "/trigger/nestedSecrets", note : "Nested secrets and a ~400KB base64 blob in extraInfo. Nested keys masked; the blob clipped with a size label; the alert builds without a pause." },
				{ route : "/trigger/messyRc", note : "Binary, a nested struct, a component and long text in rc." },
				{ route : "/trigger/htmlInjection", note : "Markup in the message. It should show as literal text." },
				{ route : "/trigger/unicode", note : "Accented Latin, CJK and emoji." },
				{ route : "/trigger/hugeMessage", note : "250KB message and detail. Each section clips long before maxBodyBytes, so the email lands around 12KB." },
				{ route : "/trigger/postForm", note : "POST, so the Request section shows POST and the form fields.", method : "POST" }
			]
		}
	];

	// Fill in the defaults so the table and the sweep can read every key.
	sweep = [];
	for ( group in groups ) {
		for ( scenario in group.scenarios ) {
			scenario.method  = scenario.method ?: "GET";
			scenario.alerts  = scenario.alerts ?: true;
			scenario.skipAll = scenario.skipAll ?: false;
			if ( !scenario.skipAll ) {
				sweep.append( { "route" : scenario.route, "method" : scenario.method } );
			}
		}
	}
</cfscript>

<cfoutput>
<h1>errorAlerts harness</h1>
<p class="lede">Each link below fails in one specific way. Fire one and read the alert it produces.</p>

<div class="status">
	<div>mailer&nbsp;&nbsp;&nbsp;= #encodeForHtml( prc.mailer )#<cfif prc.mailer eq "smtp"> &rarr; #encodeForHtml( prc.mailDefaults.server )#:#encodeForHtml( prc.mailDefaults.port )#<cfelse> (in-memory &mdash; set ERRORALERTS_MAILER=smtp in .env to send real email)</cfif></div>
	<div>alerts to = #encodeForHtml( prc.alerts.to )#</div>
	<div>throttle&nbsp;= #prc.alerts.throttle.maxPerWindow# per #prc.alerts.throttle.windowSeconds#s, digest flush every #prc.alerts.digestFlushSeconds#s</div>
	<div>database&nbsp;= #encodeForHtml( prc.database )#</div>
</div>

<p>
	<button type="button" id="fireAll">Fire all #arrayLen( sweep )# scenarios</button>
	<span class="quiet">Runs them one at a time. Takes about a minute.</span>
</p>
<div id="log"></div>

<cfloop array="#groups#" index="group">
	<h2>#encodeForHtml( group.title )#</h2>
	<p class="quiet">#encodeForHtml( group.description )#</p>
	<table>
		<cfloop array="#group.scenarios#" index="scenario">
			<tr>
				<td class="route">
					<cfif scenario.method eq "POST">
						<form method="post" action="#encodeForHtmlAttribute( scenario.route )#" style="margin:0">
							<input type="hidden" name="customerId" value="cust-4471">
							<input type="hidden" name="couponCode" value="SUMMER25">
							<button type="submit">#encodeForHtml( scenario.route )#</button>
						</form>
					<cfelse>
						<a href="#encodeForHtmlAttribute( scenario.route )#">#encodeForHtml( scenario.route )#</a>
					</cfif>
				</td>
				<td class="note">
					<cfif !scenario.alerts><strong>No email expected.</strong> </cfif>#encodeForHtml( scenario.note )#
				</td>
			</tr>
		</cfloop>
	</table>
</cfloop>

<script>
	const SWEEP = #serializeJSON( sweep )#;
	const button = document.getElementById( "fireAll" );
	const log = document.getElementById( "log" );

	button.addEventListener( "click", async () => {
		button.disabled = true;
		log.textContent = "";
		for ( let i = 0; i < SWEEP.length; i++ ) {
			const item = SWEEP[ i ];
			log.textContent += `[${ i + 1 }/${ SWEEP.length }] ${ item.route } `;
			try {
				const response = await fetch( item.route, { method: item.method, redirect: "follow" } );
				log.textContent += `-> ${ response.status }\n`;
			} catch ( error ) {
				log.textContent += `-> request failed: ${ error.message }\n`;
			}
		}
		log.textContent += "\nDone. Check your mail catcher, then hit /trigger/flushDigest for the digests.";
		button.disabled = false;
	} );
</script>
</cfoutput>
