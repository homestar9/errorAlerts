/**
 * Trigger
 *
 * Provides one action for each failure scenario.
 * Each action creates a specific error for checking the resulting alert.
 *
 * Scenarios fall into four groups:
 *
 *   - Unhandled exceptions, which reach the module through its onException
 *     interceptor because this harness sets a custom exceptionHandler.
 *   - Database query failures.
 *   - Manual LogBox calls, which reach the module through its appender.
 *   - Throttling, digest and email-rendering checks.
 *
 * Actions that should create alerts let errors escape. Other actions return a
 * short description of what they did.
 */
component {

	property name="orders"        inject="OrderService";
	property name="reportBuilder" inject="ReportBuilder";
	property name="db"            inject="DbService";

	/**
	 * index
	 *
	 * Sends visitors to the catalog page on Main.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function index( event, rc, prc ){
		relocate( "main.index" );
	}

	/* -----------------------------------------------------------------------
	 * Unhandled exceptions
	 * --------------------------------------------------------------------- */

	/**
	 * handlerThrow
	 *
	 * Throws straight from the action, so the stack is short.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function handlerThrow( event, rc, prc ){
		throw(
			type    = "Harness.Handler.Boom",
			message = "Deliberate failure in a handler action",
			detail  = "Thrown directly by Trigger.handlerThrow with nothing else on the stack."
		);
	}

	/**
	 * modelThrow
	 *
	 * Fails two components below the handler, in PaymentGateway.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function modelThrow( event, rc, prc ){
		return orders.placeOrder( customerId = "cust-4471", total = 149.99 );
	}

	/**
	 * deepStack
	 *
	 * Fails 25 frames down, so the email should show only the first 10.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function deepStack( event, rc, prc ){
		return reportBuilder.build( 25 );
	}

	/**
	 * undefinedVariable
	 *
	 * Reads a variable that was never set.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function undefinedVariable( event, rc, prc ){
		return orders.readMissingSetting();
	}

	/**
	 * typeMismatch
	 *
	 * Passes text to an argument declared numeric.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function typeMismatch( event, rc, prc ){
		return orders.applyDiscount( total = 100, percent = "twenty percent" );
	}

	/**
	 * divideByZero
	 *
	 * Divides by zero inside a model.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function divideByZero( event, rc, prc ){
		return orders.divide( top = 100, bottom = 0 );
	}

	/**
	 * missingMethod
	 *
	 * Calls a method OrderService does not have.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function missingMethod( event, rc, prc ){
		return orders.shipEverythingImmediately();
	}

	/**
	 * arrayIndex
	 *
	 * Reads position 99 of a two-item array.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function arrayIndex( event, rc, prc ){
		return orders.lineItem( 99 );
	}

	/**
	 * nullReference
	 *
	 * Calls a method on a lookup that returned nothing.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function nullReference( event, rc, prc ){
		var customer = orders.findCustomer( "cust-does-not-exist" );
		return customer.getEmailAddress();
	}

	/**
	 * viewError
	 *
	 * Renders a view that throws part-way through, after some output.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function viewError( event, rc, prc ){
		prc.invoiceNumber = "INV-20873";
		// prc.lineItems is deliberately missing.
		event.setView( "trigger/badview" );
	}

	/**
	 * layoutError
	 *
	 * Renders a working view inside a layout that throws.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function layoutError( event, rc, prc ){
		prc.title = "Quarterly summary";
		// prc.navigation is deliberately missing.
		event.setView( view = "trigger/goodview", layout = "Broken" );
	}

	/**
	 * interceptorThrow
	 *
	 * Sends the request back through preEvent with the failure flag set, so
	 * HarnessFailure throws before any action runs.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function interceptorThrow( event, rc, prc ){
		if ( !rc.keyExists( "harnessFail" ) ) {
			relocate( event = "trigger.interceptorThrow", queryString = "harnessFail=preEvent" );
			return;
		}
		return "HarnessFailure did not fire. Check that it is registered in config/Coldbox.cfc.";
	}

	/**
	 * wireboxThrow
	 *
	 * Builds a component whose init() throws, so WireBox fails.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function wireboxThrow( event, rc, prc ){
		return getInstance( "BrokenService" );
	}

	/**
	 * customType
	 *
	 * Throws a type you can add to `ignoreExceptionTypes` to confirm the setting
	 * stops the alert.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function customType( event, rc, prc ){
		throw(
			type    = "Harness.Custom.PaymentDeclined",
			message = "Payment declined for order 88213",
			detail  = "Add ""Harness.Custom.PaymentDeclined"" to ignoreExceptionTypes and this should stop alerting."
		);
	}

	/**
	 * wrappedCause
	 *
	 * Throws a high-level error with the low-level error in extendedInfo.
	 * PaymentGateway uses extendedInfo because Adobe does not support the cause
	 * argument that Lucee provides.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function wrappedCause( event, rc, prc ){
		return orders.cancelOrder( "88213" );
	}

	/**
	 * fileNotFound
	 *
	 * Reads a file that is not there.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function fileNotFound( event, rc, prc ){
		return fileRead( expandPath( "/root/config/this-file-does-not-exist.json" ) );
	}

	/**
	 * httpFailure
	 *
	 * Calls a closed port and turns the failed response into an exception.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function httpFailure( event, rc, prc ){
		cfhttp(
			url          = "http://127.0.0.1:1/health",
			method       = "GET",
			timeout      = 5,
			throwOnError = true,
			result       = "local.response"
		);
		return local.response.fileContent;
	}

	/**
	 * timeoutError
	 *
	 * Throws the kind of error a slow dependency produces.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function timeoutError( event, rc, prc ){
		throw(
			type      = "Harness.Upstream.Timeout",
			message   = "Timed out calling the inventory service",
			detail    = "No response from https://inventory.internal/api/v2/stock after 30000ms. Retried 3 times.",
			errorCode = "504"
		);
	}

	/**
	 * noSuchAction
	 *
	 * Sends the request to an action this handler does not have.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function noSuchAction( event, rc, prc ){
		relocate( "trigger.thisActionWasNeverWritten" );
	}

	/**
	 * invalidEvent
	 *
	 * Sends the request to a handler that does not exist.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function invalidEvent( event, rc, prc ){
		relocate( "noSuchHandler.noSuchAction" );
	}

	/* -----------------------------------------------------------------------
	 * Database query failures
	 * --------------------------------------------------------------------- */

	/**
	 * dbSyntax
	 *
	 * Runs SQL the database cannot parse.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbSyntax( event, rc, prc ){
		return db.syntaxError();
	}

	/**
	 * dbMissingTable
	 *
	 * Selects from a table that does not exist.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbMissingTable( event, rc, prc ){
		return db.missingTable();
	}

	/**
	 * dbMissingColumn
	 *
	 * Selects a column the table does not have.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbMissingColumn( event, rc, prc ){
		return db.missingColumn();
	}

	/**
	 * dbConstraint
	 *
	 * Inserts a duplicate primary key.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbConstraint( event, rc, prc ){
		return db.constraintViolation();
	}

	/**
	 * dbInTransaction
	 *
	 * Fails on the second insert inside a transaction, so the first rolls back.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbInTransaction( event, rc, prc ){
		return db.transactionFailure();
	}

	/**
	 * dbBadParam
	 *
	 * Binds text to an integer query parameter.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbBadParam( event, rc, prc ){
		return db.badParameter();
	}

	/**
	 * dbNoDatasource
	 *
	 * Queries a datasource name that was never declared. Works on every engine.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbNoDatasource( event, rc, prc ){
		return db.undefinedDatasource();
	}

	/**
	 * dbDeadHost
	 *
	 * Queries a datasource pointed at a closed port.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function dbDeadHost( event, rc, prc ){
		return db.deadConnection();
	}

	/* -----------------------------------------------------------------------
	 * Manual LogBox messages
	 * --------------------------------------------------------------------- */

	/**
	 * logError
	 *
	 * Logs an error with no exception attached, so the email has no Exception
	 * section.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logError( event, rc, prc ){
		logger( "orders.checkout" ).error(
			"Checkout finished with 3 unprocessed payments and no exception was thrown"
		);
		return sent( "log.error() with no extraInfo" );
	}

	/**
	 * logErrorWithException
	 *
	 * Catches an exception and logs it, which is the common pattern in real code.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logErrorWithException( event, rc, prc ){
		try {
			orders.placeOrder( customerId = "cust-9982" );
		} catch ( any e ) {
			logger( "orders.checkout" ).error( "Order 9982 could not be placed: #e.message#", e );
		}
		return sent( "log.error() with a caught exception as extraInfo" );
	}

	/**
	 * logErrorWithData
	 *
	 * Passes a plain struct as extraInfo, which fills the Extra info section
	 * rather than the Exception section.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logErrorWithData( event, rc, prc ){
		logger( "orders.reconciliation" ).error(
			"Nightly reconciliation found mismatched totals",
			{
				batchId     : "batch-2026-07-27",
				expected    : 481203.55,
				actual      : 481199.10,
				difference  : 4.45,
				accounts    : [ "AC-1001", "AC-1002", "AC-1188" ],
				runDuration : "00:04:12"
			}
		);
		return sent( "log.error() with a plain struct as extraInfo" );
	}

	/**
	 * logFatal
	 *
	 * Logs at FATAL, the top of the alerting range.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logFatal( event, rc, prc ){
		logger( "scheduler.nightlyBilling" ).fatal(
			"Nightly billing aborted: the billing queue is unreachable"
		);
		return sent( "log.fatal()" );
	}

	/**
	 * logWarn
	 *
	 * Logs below the alerting range. This must not produce an email.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logWarn( event, rc, prc ){
		logger( "orders.checkout" ).warn( "Payment retried once before succeeding" );
		return notSent( "WARN is below levelMin, which defaults to FATAL..ERROR" );
	}

	/**
	 * logInfo
	 *
	 * Logs well below the alerting range. This must not produce an email.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logInfo( event, rc, prc ){
		logger( "orders.checkout" ).info( "Order 12345 completed" );
		return notSent( "INFO is below levelMin" );
	}

	/**
	 * logIgnoredCategory
	 *
	 * Logs an error under a category that starts with an ignored prefix. This
	 * must not produce an email.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logIgnoredCategory( event, rc, prc ){
		logger( "cbmailservices.harness" ).error( "Alert email itself failed to send" );
		return notSent( "the category starts with ""cbmailservices"", which is in ignoreCategories" );
	}

	/**
	 * logFromThread
	 *
	 * Logs an error from a background thread with no request context.
	 * The alert should use empty request and rc sections.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logFromThread( event, rc, prc ){
		// Pass the logger as an attribute because the thread cannot use variables.
		var jobLogger = logger( "jobs.import" );

		thread name="harnessBackgroundFailure" jobLogger=jobLogger {
			try {
				throw(
					type    = "Harness.Background.JobFailed",
					message = "Background import job failed outside any request",
					detail  = "Thrown inside a thread, so there is no ColdBox event or request collection."
				);
			} catch ( any e ) {
				attributes.jobLogger.error( "Import job failed: #e.message#", e );
			}
		}

		cfthread( action = "join", name = "harnessBackgroundFailure", timeout = 5000 );
		return sent( "log.error() from a background thread with no request context" );
	}

	/**
	 * taskFailure
	 *
	 * Makes the harness's ColdBox scheduled task fail on its next run, within
	 * about a second. The task thread carries a copy of the request that started
	 * the application. The alert should say "scheduled task (pool-N-thread-M)"
	 * and show no URL, event, rc, or other row from that copied request.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function taskFailure( event, rc, prc ){
		getInstance( "appScheduler@coldbox" ).armFailure();
		return sent( "a log.error() from the scheduled task's onFailure() handler, about a second from now" );
	}

	/* -----------------------------------------------------------------------
	 * Throttling and digests
	 * --------------------------------------------------------------------- */

	/**
	 * burst
	 *
	 * Logs the same error ten times. The first three alert and the rest are
	 * counted for the digest.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function burst( event, rc, prc ){
		for ( var i = 1; i <= 10; i++ ) {
			logger( "orders.checkout" ).error( "Payment provider connection refused" );
		}
		return sent(
			"the same error 10 times. Expect 3 emails now, then a digest for the other 7 once the window closes. Use /trigger/flushDigest to get it immediately."
		);
	}

	/**
	 * burstVariants
	 *
	 * Logs ten errors that differ only by numbers and ids. Signature
	 * normalization should treat them as one error.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function burstVariants( event, rc, prc ){
		for ( var i = 1; i <= 10; i++ ) {
			logger( "orders.checkout" ).error(
				"Order #randRange( 10000, 99999 )# failed validation (ref #createUUID()#)"
			);
		}
		return sent(
			"10 errors that differ only by numbers and UUIDs. normalizeSignatures should collapse them into one signature, so expect 3 emails, not 10."
		);
	}

	/**
	 * burstDistinct
	 *
	 * Logs five genuinely different errors, so each gets its own window.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function burstDistinct( event, rc, prc ){
		var messages = [
			"Inventory service returned 503",
			"Shipping label API rejected the address",
			"Tax calculation returned a negative amount",
			"Customer record is missing an email address",
			"Warehouse queue is full"
		];
		for ( var message in messages ) {
			logger( "orders.fulfillment" ).error( message );
		}
		return sent( "5 different errors. Each has its own signature, so expect 5 emails." );
	}

	/**
	 * flushDigest
	 *
	 * Sends the digest for any window that has already expired, instead of
	 * waiting for the scheduler.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function flushDigest( event, rc, prc ){
		getInstance( "CaptureService@errorAlerts" ).flushDigests();
		return sent( "a digest for every expired throttle window. Nothing arrives if no window has closed yet." );
	}

	/**
	 * throttleStatus
	 *
	 * Shows throttle settings and the current mailer without sending an alert.
	 * ThrottleService keeps its live window counts private.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function throttleStatus( event, rc, prc ){
		var settings = getSetting( "moduleSettings" ).errorAlerts;
		var mail     = getSetting( "moduleSettings" ).cbmailservices;

		var lines = [
			"levelMin..levelMax = #settings.levelMin#..#settings.levelMax#",
			"maxPerWindow       = #settings.throttle.maxPerWindow#",
			"windowSeconds      = #settings.throttle.windowSeconds#",
			"digestFlushSeconds = #settings.digestFlushSeconds#",
			"deliveryMode       = #settings.deliveryMode#",
			"to                 = #settings.to#",
			"mailer             = #mail.defaultProtocol#"
		];

		if ( mail.defaultProtocol == "smtp" ) {
			lines.append( "smtp               = #mail.defaults.server#:#mail.defaults.port#" );
		} else {
			lines.append( "in-memory mailbox  = #mailboxSize()# email(s). View the newest at /main/lastMail." );
		}

		return lines.toList( chr( 10 ) );
	}

	/**
	 * reset
	 *
	 * Clears every throttle window and empties the in-memory mailbox.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function reset( event, rc, prc ){
		getInstance( "ThrottleService@errorAlerts" ).reset();
		try {
			getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.reset();
		} catch ( any e ) {
		}
		return "Throttle windows cleared and the in-memory mailbox emptied.";
	}

	/* -----------------------------------------------------------------------
	 * Email content checks
	 * --------------------------------------------------------------------- */

	/**
	 * maskedRc
	 *
	 * Fails with sensitive-looking values in the request collection, so the
	 * email can be checked for masking.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function maskedRc( event, rc, prc ){
		rc.password         = "hunter2";
		rc.api_key          = "sk-live-9f3a2b71c4d8";
		rc.authorization    = "Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature";
		rc.creditCardNumber = "4111 1111 1111 1111";
		rc.cvv              = "737";
		rc.orderId          = "88213";
		rc.customerEmail    = "ada@example.com";

		throw(
			type    = "Harness.Rc.Masking",
			message = "Failure with secrets in the request collection",
			detail  = "password, api_key, authorization, creditCardNumber and cvv should all read *** masked ***. orderId and customerEmail should be readable. Note that cgi.query_string in the Request section above is NOT masked."
		);
	}

	/**
	 * nestedSecrets
	 *
	 * Logs nested secrets and a large base64 value in extraInfo and rc.
	 * The alert demonstrates nested masking, value limits, and bounded processing.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function nestedSecrets( event, rc, prc ){
		rc.profile = { name : "Ada Lovelace", ssn : "123-45-6789", password : "hunter2" };

		logger( "orders.documents" ).error(
			"Contract PDF generation failed",
			{
				"document" : {
					"fileName"    : "contract.pdf",
					"fileContent" : toBase64( repeatString( "fake-pdf-bytes-", 20000 ) )
				},
				"vendorAuth" : {
					"apikey"   : "sk-live-9f3a2b71c4d8",
					"endpoint" : "https://api.example.com/charge"
				}
			}
		);
		return sent(
			"one error with nested secrets and a ~400 KB base64 blob. In the email: " &
			"vendorAuth.apikey and rc.profile.password read *** masked ***, fileContent " &
			"shows a 500-character prefix plus a size label, and rc.profile.ssn stays " &
			"readable because the harness never added ssn to maskKeys - masking is opt-in"
		);
	}

	/**
	 * messyRc
	 *
	 * Fails with awkward value types in the request collection, so every branch
	 * of the sanitizer can be seen at once.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function messyRc( event, rc, prc ){
		rc.longText   = repeatString( "The quick brown fox jumps over the lazy dog. ", 120 );
		rc.binaryBlob = toBinary( toBase64( repeatString( "x", 512 ) ) );
		rc.nested     = {
			customer : { id : 4471, name : "Ada Lovelace", tags : [ "vip", "beta" ] },
			totals   : { subTotal : 129.99, tax : 10.40, grand : 140.39 }
		};
		rc.component  = getInstance( "OrderService" );
		rc.emptyValue = "";
		rc.aNumber    = 42;
		rc.aBoolean   = true;
		rc.aDate      = now();

		throw(
			type    = "Harness.Rc.MixedTypes",
			message = "Failure with mixed value types in the request collection",
			detail  = "Long text should be clipped, the blob should read as binary bytes, the component should read as an object name, and the nested struct should be serialized."
		);
	}

	/**
	 * htmlInjection
	 *
	 * Puts markup in the exception message and the request collection so the
	 * email can be checked for escaping.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function htmlInjection( event, rc, prc ){
		rc.searchTerm = "<img src=x onerror=alert(1)>";
		throw(
			type    = "Harness.Rendering.HtmlInjection",
			message = "Search failed for <script>alert('xss')</script> & other input",
			detail  = "All of this should show as literal text in the email: <b>bold</b>, <a href='##'>link</a>, ""quotes"" & ampersands."
		);
	}

	/**
	 * unicode
	 *
	 * Fails with non-ASCII text so the email charset can be checked.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function unicode( event, rc, prc ){
		rc.customerName = "Zoë Müller-Škoda";
		throw(
			type    = "Harness.Rendering.Unicode",
			message = "Café order failed 💥 for Zoë Müller-Škoda (東京支店)",
			detail  = "Accented Latin, CJK and emoji should all survive: àéîõü — ñ — 日本語 — 🚨 🔥 ✅"
		);
	}

	/**
	 * hugeMessage
	 *
	 * Uses an oversized message and detail to show output truncation.
	 * EmailRenderer limits the message section before the full email limit applies.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function hugeMessage( event, rc, prc ){
		throw(
			type    = "Harness.Rendering.Oversized",
			message = "Bulk import failed. " & repeatString(
				"Row rejected because the SKU is unknown and the warehouse code is missing. ",
				3000
			),
			detail  = repeatString( "Detail line that pushes the email past its byte budget. ", 3000 )
		);
	}

	/**
	 * postForm
	 *
	 * Fails on a POST so the email shows POST as the request method and the form
	 * fields in the request collection. The catalog page posts to this action.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function postForm( event, rc, prc ){
		throw(
			type    = "Harness.Request.PostFailure",
			message = "Form submission failed during validation",
			detail  = "The email's Request section should show method POST and the submitted fields in rc."
		);
	}

	/* -----------------------------------------------------------------------
	 * Helpers
	 * --------------------------------------------------------------------- */

	/**
	 * logger
	 *
	 * Returns a LogBox logger for a specific category.
	 * The injected handler logger cannot provide the different categories needed
	 * by these scenarios.
	 *
	 * @category The logger category name.
	 */
	private any function logger( required string category ){
		return controller.getLogBox().getLogger( arguments.category );
	}

	/**
	 * mailboxSize
	 *
	 * Returns how many emails the in-memory mailer is holding, or -1 when the
	 * in-memory mailer is not configured.
	 */
	private numeric function mailboxSize(){
		try {
			return getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.getMail().len();
		} catch ( any e ) {
			return -1;
		}
	}

	/**
	 * sent
	 *
	 * Returns a confirmation line for scenarios that log rather than throw.
	 *
	 * @what What was logged.
	 */
	private string function sent( required string what ){
		return "Logged #arguments.what#. Check your mail catcher.";
	}

	/**
	 * notSent
	 *
	 * Returns a line for scenarios that deliberately produce no email.
	 *
	 * @why Why nothing was sent.
	 */
	private string function notSent( required string why ){
		return "No alert expected: #arguments.why#. If an email arrives, that is a bug.";
	}

}
