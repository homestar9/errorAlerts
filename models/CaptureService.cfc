/**
 * CaptureService
 *
 * Filters and throttles captured log events before sending notifications.
 * Internal failures go to System.err. This keeps them out of the request and
 * prevents another LogBox event.
 *
 * captureException() is the public entry point for unhandled exceptions. The
 * interceptor uses it for ColdBox requests. Code outside ColdBox, such as an
 * Application.cfc onError() method for older pages in the same application,
 * can call it directly.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings"         inject="coldbox:moduleSettings:errorAlerts";
	property name="signatureService" inject="SignatureService@errorAlerts";
	property name="throttleService"  inject="ThrottleService@errorAlerts";
	property name="payloadBuilder"   inject="PayloadBuilder@errorAlerts";
	property name="threadClassifier" inject="ThreadClassifier@errorAlerts";
	property name="wirebox"          inject="wirebox";
	property name="coldbox"          inject="coldbox";

	/**
	 * init
	 *
	 * Stores the Java System object used to write failures to System.err.
	 */
	function init(){
		variables.system = createObject( "java", "java.lang.System" );

		// Store keys for at most 50 reported errors per request, even if onError() runs in a loop.
		variables.MAX_REPORTED_PER_REQUEST = 50;

		// Match the exception types that engines use for aborts and redirects.
		variables.ABORT_TYPE_PATTERN = "(^|\.)Abort(Exception)?$";

		// Double the request limit at most this many times while it is still exceeded.
		variables.MAX_TIMEOUT_PROBES = 20;

		// Cap failure text written to System.err. cbmailservices includes full stack traces.
		variables.MAX_FAILURE_TEXT = 500;

		return this;
	}

	/**
	 * capture
	 *
	 * Checks, throttles, and sends one log event.
	 * Also sends a digest when this event closes an expired throttle window.
	 *
	 * Check enabled each time this method runs, not just when the module loads.
	 * WireBox can create this service even when the module did not register its
	 * appender and interceptor. For example, a development() override may disable
	 * the module. Direct calls must still respect that setting.
	 *
	 * Returns false only when the event's own alert failed: this method's catch
	 * ran, or the notifier threw. Deliberate skips return true because they are
	 * decisions, not failures: disabled, ignored, a duplicate framework log, or
	 * suppressed by the throttle. A failed digest does not count, because the
	 * digest window is already gone and a retry would only repeat the alert.
	 * captureException() uses the result to decide whether a retry may send.
	 * The throttle has already counted a failed attempt, so a retry is the next
	 * occurrence. The appender ignores the result.
	 *
	 * @logEvent The LogBox LogEvent to process.
	 */
	boolean function capture( required any logEvent ){
		try {
			if ( !settings.enabled ) {
				return true;
			}

			if ( isIgnored( arguments.logEvent ) ) {
				return true;
			}

			if ( isDuplicateFrameworkLog( arguments.logEvent ) ) {
				return true;
			}

			var signature = signatureService.compute( arguments.logEvent );
			var verdict   = throttleService.record(
				signature = signature,
				snapshot  = buildSnapshot( arguments.logEvent )
			);

			if ( !verdict.expiredDigest.isEmpty() ) {
				sendDigest( verdict.expiredDigest );
			}

			if ( verdict.action != "SEND" ) {
				return true;
			}

			return dispatch( payloadBuilder.build( arguments.logEvent, signature, verdict.occurrence ) );
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts capture failed: " & failureText( e ) );
			return false;
		}
	}

	/**
	 * captureException
	 *
	 * Reports an unhandled exception by passing it to capture().
	 * Application.cfc onError() methods and the module's interceptor call this
	 * method. It never throws an exception back to the caller because a failed
	 * alert must not stop the application's error handler.
	 *
	 * Adobe wraps an exception thrown inside an Application.cfc event method in
	 * an EventHandlerException. Use the original exception for the email and
	 * for checks that group matching errors or prevent duplicate reports.
	 * Ignore aborts and redirects because they are not errors.
	 *
	 * Track reported errors to prevent a second report of the same exception
	 * within a request. This covers a handler that rethrows an exception already
	 * reported by the interceptor, causing onError() to run. Record an exception
	 * only after capture() succeeds, so onError() can retry one whose first
	 * alert failed. The request flag prevents this method from running again
	 * while a capture is in progress.
	 *
	 * Extend a request that is already past its time limit before anything
	 * else runs. See extendTimedOutRequest().
	 *
	 * @exception The cfcatch struct or exception object to report.
	 */
	void function captureException( required any exception ){
		try {
			if ( !settings.enabled || request.keyExists( "_errorAlertsCapturing" ) ) {
				return;
			}

			var target = unwrapHandlerException( arguments.exception );
			if ( isAbort( target ) ) {
				return;
			}

			extendTimedOutRequest();
			ensureModuleMappings();

			if ( !request.keyExists( "_errorAlertsReported" ) ) {
				request._errorAlertsReported = {};
			}
			var key = requestFingerprint( target );
			if ( request._errorAlertsReported.keyExists( key ) ) {
				return;
			}

			var captured = false;
			request._errorAlertsCapturing = true;
			try {
				captured = capture( newUnhandledEvent( target ) );
			} finally {
				request.delete( "_errorAlertsCapturing" );
			}

			if ( captured && structCount( request._errorAlertsReported ) < variables.MAX_REPORTED_PER_REQUEST ) {
				request._errorAlertsReported[ key ] = true;
			}
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts captureException failed: #e.message# #e.detail#" );
		}
	}

	/**
	 * flushDigests
	 *
	 * Sends digests for all expired throttle windows.
	 */
	void function flushDigests(){
		try {
			var seeds = throttleService.flushExpired();
			for ( var seed in seeds ) {
				sendDigest( seed );
			}
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts digest flush failed: #e.message# #e.detail#" );
		}
	}

	/**
	 * setNotifier
	 *
	 * Replaces the cached notifier.
	 *
	 * @notifier Any object implementing INotifier's sendNotification().
	 */
	any function setNotifier( required any notifier ){
		variables.notifier = arguments.notifier;
		return this;
	}

	/**
	 * getNotifier
	 *
	 * Loads the configured WireBox notifier once and returns it.
	 */
	any function getNotifier(){
		if ( !variables.keyExists( "notifier" ) ) {
			variables.notifier = wirebox.getInstance( settings.notifier );
		}
		return variables.notifier;
	}

	/**
	 * isIgnored
	 *
	 * Checks the category prefix, exception type, and message pattern ignore lists.
	 *
	 * @logEvent The LogBox LogEvent to test.
	 */
	private boolean function isIgnored( required any logEvent ){
		var category = arguments.logEvent.getCategory();
		for ( var prefix in settings.ignoreCategories ) {
			if ( category.findNoCase( prefix ) == 1 ) {
				return true;
			}
		}

		if ( settings.ignoreExceptionTypes.len() ) {
			var extraInfo = arguments.logEvent.getExtraInfo();
			// Adobe ColdFusion cfcatch values can be objects instead of structs.
			// Use structKeyExists() so both forms can be checked safely.
			if (
				( isObject( extraInfo ) || isStruct( extraInfo ) )
				&& structKeyExists( extraInfo, "type" )
				&& isSimpleValue( extraInfo.type )
				&& settings.ignoreExceptionTypes.findNoCase( extraInfo.type )
			) {
				return true;
			}
		}

		if ( settings.ignoreMessagePatterns.len() && matchesIgnoredMessage( arguments.logEvent ) ) {
			return true;
		}

		return false;
	}

	/**
	 * matchesIgnoredMessage
	 *
	 * Checks the log message, and the message and detail of an exception passed
	 * as extraInfo, against each ignoreMessagePatterns entry. An unhandled
	 * exception's log message already contains its message and detail. A logged
	 * error usually has its own message, so the exception fields are checked too.
	 *
	 * Skip a pattern the regex engine rejects instead of failing the whole check.
	 * A bad pattern then ignores nothing rather than stopping every alert.
	 *
	 * @logEvent The LogBox LogEvent to test.
	 */
	private boolean function matchesIgnoredMessage( required any logEvent ){
		var texts     = [ arguments.logEvent.getMessage() ];
		var extraInfo = arguments.logEvent.getExtraInfo();
		texts.append( fieldText( extraInfo, "message" ) );
		texts.append( fieldText( extraInfo, "detail" ) );

		for ( var pattern in settings.ignoreMessagePatterns ) {
			for ( var text in texts ) {
				if ( !len( text ) ) {
					continue;
				}
				try {
					if ( reFindNoCase( pattern, text ) ) {
						return true;
					}
				} catch ( any e ) {
					// An invalid pattern can never match. Try the next one.
					break;
				}
			}
		}

		return false;
	}

	/**
	 * isDuplicateFrameworkLog
	 *
	 * Checks whether RestHandler will report this log event again through
	 * onException. The interceptor captures the second report, so keeping both
	 * would send two emails.
	 *
	 * The onException report is kept because its tagContext provides stack frames
	 * and source code. The logged copy only has _stacktrace and httpData.
	 *
	 * The message prefix separates these duplicates from RestHandler.onError().
	 * onError() uses the same extraInfo fields but does not announce onException.
	 * Matching only the fields would cause a lost alert. If ColdBox changes the
	 * message, this check may allow a duplicate but will not drop the only copy.
	 *
	 * @logEvent The LogBox LogEvent to test.
	 */
	private boolean function isDuplicateFrameworkLog( required any logEvent ){
		if ( !settings.suppressDuplicateFrameworkLogs ) {
			return false;
		}

		var extraInfo = arguments.logEvent.getExtraInfo();
		// Adobe ColdFusion cfcatch values can be objects instead of structs.
		// Use structKeyExists() so both forms can be checked safely.
		if (
			!( isObject( extraInfo ) || isStruct( extraInfo ) )
			|| !structKeyExists( extraInfo, "_stacktrace" )
			|| !structKeyExists( extraInfo, "httpData" )
			|| structKeyExists( extraInfo, "tagContext" )
		) {
			return false;
		}

		// findNoCase() == 1 means the message starts with this text.
		return arguments.logEvent.getMessage().findNoCase( "Error calling " ) == 1;
	}

	/**
	 * ensureModuleMappings
	 *
	 * Reloads the mappings that tell CFML where ColdBox module code lives.
	 * Lucee and BoxLang keep mappings added at runtime for one request only.
	 * ColdBox reloads them when it starts handling each request. If
	 * onRequestStart() fails before ColdBox runs, onError() has no cbmailservices
	 * mapping. The first mail build then fails, and WireBox removes the mail
	 * object mapping after that failure. Later alerts fail until the application
	 * is reinitialized. Adobe keeps mappings for the whole application, so the
	 * reload is not needed there. If this reload fails, still try to capture.
	 */
	private void function ensureModuleMappings(){
		try {
			coldbox.getModuleService().loadMappings();
		} catch ( any e ) {
		}
	}

	/**
	 * extendTimedOutRequest
	 *
	 * Gives a request that is already past its time limit enough time to send
	 * the alert and render the application's error page. Both engines that
	 * enforce the limit measure it from the start of the request, so adding
	 * seconds to the current limit is not enough when one long query ran well
	 * past it. The limit only grows.
	 *
	 * - Adobe throws the timeout again at every later cfoutput, cfquery or
	 *   cfmail. See extendAdobeRequest().
	 * - Lucee stops the request from a controller thread, and stops it again
	 *   on a later pass, while onError() is still reporting the first timeout.
	 *   That second stop is an abort no catch can handle. See
	 *   extendLuceeRequest().
	 * - BoxLang does not enforce the limit, so it needs nothing.
	 *
	 * Runs at most once per request, and only when the request is past its
	 * limit. That is false when the application already extended it. The
	 * cheapest checks run first. A value below 1 turns this off, because a
	 * limit of 0 would remove the request's time limit. Failures are ignored.
	 */
	private void function extendTimedOutRequest(){
		try {
			var extension = int( val( settings.timeoutExtensionSeconds ) );
			if ( extension < 1 || request.keyExists( "_errorAlertsTimeoutExtended" ) ) {
				return;
			}

			var engine   = currentEngine();
			var extended = false;
			if ( engine == "adobe" ) {
				extended = extendAdobeRequest( extension );
			} else if ( engine == "lucee" ) {
				extended = extendLuceeRequest( extension );
			}

			if ( extended ) {
				request._errorAlertsTimeoutExtended = true;
			}
		} catch ( any e ) {
		}
	}

	/**
	 * extendAdobeRequest
	 *
	 * Extends an Adobe request that Adobe reports is past its limit, and
	 * returns whether it did. Adobe's report is false when its timeout option
	 * is off and in a cfthread. Adobe exposes no start time that matches its own
	 * clock, so the limit is doubled until Adobe reports the request is within
	 * it, then extended once more.
	 *
	 * @extension Whole seconds to leave after the current moment.
	 */
	private boolean function extendAdobeRequest( required numeric extension ){
		if ( !adobeRequestTimedOut() ) {
			return false;
		}

		var limit = max( adobeRequestTimeoutSeconds(), 1 ) + arguments.extension;
		applyRequestTimeout( limit );

		var probes = 0;
		while ( probes < variables.MAX_TIMEOUT_PROBES && adobeRequestTimedOut() ) {
			probes++;
			limit = limit * 2;
			applyRequestTimeout( limit );
		}

		// The request is now within the limit. Leave a full extension after it.
		if ( probes > 0 ) {
			limit = limit + arguments.extension;
			applyRequestTimeout( limit );
		}

		return true;
	}

	/**
	 * extendLuceeRequest
	 *
	 * Extends a Lucee request that is past its limit, and returns whether it
	 * did. Lucee's controller compares the page context's start time plus its
	 * limit with the clock, so the elapsed time is exact here.
	 *
	 * @extension Whole seconds to leave after the current moment.
	 */
	private boolean function extendLuceeRequest( required numeric extension ){
		var elapsedMs = luceeElapsedMs();
		if ( elapsedMs <= luceeRequestTimeoutMs() ) {
			return false;
		}

		var limit = ceiling( elapsedMs / 1000 ) + arguments.extension;
		applyRequestTimeout( limit );
		return true;
	}

	/**
	 * currentEngine
	 *
	 * Returns "adobe", "lucee", "boxlang", or an empty string. ThreadClassifier
	 * caches the engine name. A separate method, so specs can choose the engine.
	 */
	private string function currentEngine(){
		return threadClassifier.engineName();
	}

	/**
	 * luceeElapsedMs
	 *
	 * Returns how long the Lucee request has run, on the clock Lucee's
	 * controller uses. A separate method, so specs can stub it.
	 */
	private numeric function luceeElapsedMs(){
		return getTickCount() - getPageContext().getStartTime();
	}

	/**
	 * luceeRequestTimeoutMs
	 *
	 * Returns the Lucee request's limit in milliseconds. A separate method, so
	 * specs can stub it.
	 */
	private numeric function luceeRequestTimeoutMs(){
		return getPageContext().getRequestTimeout();
	}

	/**
	 * adobeRequestTimedOut
	 *
	 * Returns Adobe's own answer to whether the request is past its limit. A
	 * separate method, so specs can stub it.
	 */
	private boolean function adobeRequestTimedOut(){
		return requestMonitor().isRequestTimedOut();
	}

	/**
	 * adobeRequestTimeoutSeconds
	 *
	 * Returns the request's current limit in seconds. A separate method, so
	 * specs can stub it.
	 */
	private numeric function adobeRequestTimeoutSeconds(){
		return requestMonitor().getRequestTimeout();
	}

	/**
	 * applyRequestTimeout
	 *
	 * Sets the request's limit, measured from the start of the request, on
	 * Adobe and Lucee. On Adobe the setting statement updates both places the
	 * limit is stored. A separate method, so specs can record the values.
	 *
	 * @seconds The new limit in whole seconds.
	 */
	private void function applyRequestTimeout( required numeric seconds ){
		setting requestTimeout = arguments.seconds;
	}

	/**
	 * requestMonitor
	 *
	 * Returns Adobe's coldfusion.runtime.RequestMonitor class, created once.
	 * Only Adobe code paths call this.
	 */
	private any function requestMonitor(){
		if ( !variables.keyExists( "requestMonitorClass" ) ) {
			variables.requestMonitorClass = createObject( "java", "coldfusion.runtime.RequestMonitor" );
		}
		return variables.requestMonitorClass;
	}

	/**
	 * newUnhandledEvent
	 *
	 * Converts an exception to the LogEvent that capture() accepts.
	 * The message format and category help identify matching errors for throttling.
	 * Changing either makes existing errors count as new groups with new time
	 * windows for limiting alerts.
	 *
	 * @exception The cfcatch struct or exception object being reported.
	 */
	private any function newUnhandledEvent( required any exception ){
		return new coldbox.system.logging.LogEvent(
			message   = "Unhandled exception: "
			& fieldText( arguments.exception, "message" )
			& " "
			& fieldText( arguments.exception, "detail" ),
			severity  = 1, // LogBox ERROR
			extraInfo = arguments.exception,
			category  = "UnhandledException"
		);
	}

	/**
	 * unwrapHandlerException
	 *
	 * Returns the original exception from an Adobe EventHandlerException.
	 * Adobe puts errors from onRequest() or onRequestStart() inside this wrapper
	 * before passing them to onError(). Only remove this kind of wrapper.
	 * Other Adobe exceptions also have rootCause, so that key alone does not
	 * mean the error is wrapped. Return the input unchanged if no wrapper is found.
	 *
	 * @exception The cfcatch struct or exception object from onError().
	 */
	private any function unwrapHandlerException( required any exception ){
		try {
			if ( !isExceptionLike( arguments.exception ) ) {
				return arguments.exception;
			}

			var isWrapper = fieldText( arguments.exception, "type" ).findNoCase( "EventHandlerException" )
				|| fieldText( arguments.exception, "message" ) == "Event Handler Exception.";

			if (
				isWrapper
				&& structKeyExists( arguments.exception, "rootCause" )
				&& !isNull( arguments.exception.rootCause )
				&& isExceptionLike( arguments.exception.rootCause )
			) {
				return arguments.exception.rootCause;
			}
		} catch ( any e ) {
		}

		return arguments.exception;
	}

	/**
	 * isAbort
	 *
	 * Checks whether the exception represents an abort or redirect.
	 * Adobe can pass coldfusion.runtime.AbortException to onError() after a
	 * location() or abort inside onRequestStart(). Lucee and BoxLang handle
	 * aborts separately, but their abort types are checked too. Also check the
	 * cause in case another exception contains the abort.
	 *
	 * @exception The cfcatch struct or exception object to test.
	 */
	private boolean function isAbort( required any exception ){
		try {
			if ( !isExceptionLike( arguments.exception ) ) {
				return false;
			}

			if ( isAbortType( fieldText( arguments.exception, "type" ) ) ) {
				return true;
			}

			// Adobe uses rootCause. Lucee and BoxLang use cause.
			for ( var key in [ "rootCause", "cause" ] ) {
				if (
					structKeyExists( arguments.exception, key )
					&& !isNull( arguments.exception[ key ] )
					&& isExceptionLike( arguments.exception[ key ] )
					&& isAbortType( fieldText( arguments.exception[ key ], "type" ) )
				) {
					return true;
				}
			}
		} catch ( any e ) {
		}

		return false;
	}

	/**
	 * isAbortType
	 *
	 * Matches the abort type name on every supported engine, for example
	 * coldfusion.runtime.AbortException, lucee.runtime.exp.Abort, and
	 * ortus.boxlang.runtime.types.exceptions.AbortException.
	 *
	 * @type The exception type text.
	 */
	private boolean function isAbortType( required string type ){
		return reFindNoCase( variables.ABORT_TYPE_PATTERN, arguments.type.trim() ) > 0;
	}

	/**
	 * requestFingerprint
	 *
	 * Returns a hash used to find duplicate reports within one request.
	 * Use the exception's type, message, detail, and first stack frame unchanged.
	 * SignatureService can replace numbers or UUIDs in messages; this method does not.
	 * This keeps the duplicate check separate from the grouping of repeated alerts.
	 *
	 * @exception The cfcatch struct or exception object to identify.
	 */
	private string function requestFingerprint( required any exception ){
		var parts = [
			fieldText( arguments.exception, "type" ),
			fieldText( arguments.exception, "message" ),
			fieldText( arguments.exception, "detail" ),
			topFrameText( arguments.exception )
		];
		return hash( parts.toList( "|" ), "MD5" );
	}

	/**
	 * topFrameText
	 *
	 * Returns the first stack frame's file path and line number as "template:line".
	 * Returns an empty string if the frame cannot be read.
	 *
	 * @exception The cfcatch struct or exception object.
	 */
	private string function topFrameText( required any exception ){
		try {
			if (
				isExceptionLike( arguments.exception )
				&& structKeyExists( arguments.exception, "tagContext" )
				&& isArray( arguments.exception.tagContext )
				&& arguments.exception.tagContext.len()
			) {
				var frame = arguments.exception.tagContext[ 1 ];
				return fieldText( frame, "template" ) & ":" & fieldText( frame, "line" );
			}
		} catch ( any e ) {
		}
		return "";
	}

	/**
	 * fieldText
	 *
	 * Reads an exception field, such as message or detail, as text.
	 * Returns an empty string if the field is missing, null, or cannot be read.
	 * Values that isSimpleValue() rejects, such as arrays or structs, also return
	 * an empty string.
	 * Reading a null Java exception message directly throws on some engines.
	 * Returning an empty string lets the alert still report the other fields.
	 *
	 * @source The cfcatch struct or exception object.
	 * @key    The field to read.
	 */
	private string function fieldText( required any source, required string key ){
		try {
			if ( !isExceptionLike( arguments.source ) || !structKeyExists( arguments.source, arguments.key ) ) {
				return "";
			}
			var value = arguments.source[ arguments.key ];
			if ( isNull( value ) || !isSimpleValue( value ) ) {
				return "";
			}
			return toString( value );
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * isExceptionLike
	 *
	 * Returns true for a struct or object that can hold exception fields.
	 * Adobe cfcatch values can be objects instead of structs.
	 *
	 * @value A value of any type to check.
	 */
	private boolean function isExceptionLike( required any value ){
		return isObject( arguments.value ) || isStruct( arguments.value );
	}

	/**
	 * hasColdBoxContext
	 *
	 * Checks whether ColdBox routed the current request.
	 * Check contextExists() before calling getContext(), because getContext()
	 * creates a context if one is missing. Then check for a non-empty event name.
	 * Code outside ColdBox can create an empty context by calling WireBox.
	 * That empty context does not count as a ColdBox request. Keep this method
	 * identical to the copy in PayloadBuilder.
	 */
	private boolean function hasColdBoxContext(){
		var requestService = coldbox.getRequestService();
		if ( !requestService.contextExists() ) {
			return false;
		}
		return requestService.getContext().getCurrentEvent().len() > 0;
	}

	/**
	 * buildSnapshot
	 *
	 * Returns the event details needed for a later digest.
	 * The route and client address help show whether failures came from one page
	 * or many requests. A page outside ColdBox uses its file path as the route.
	 * If a value cannot be read, that value stays blank.
	 *
	 * A scheduled task or other ColdBox async thread leaves both blank. Its
	 * request data is a copy of the request that created the thread, so the
	 * digest would otherwise list that unrelated route and client.
	 *
	 * @logEvent The LogBox LogEvent being recorded.
	 */
	private struct function buildSnapshot( required any logEvent ){
		var snapshot = {
			message   : arguments.logEvent.getMessage().left( 500 ),
			category  : arguments.logEvent.getCategory(),
			severity  : arguments.logEvent.getSeverity(),
			timestamp : arguments.logEvent.getTimestamp(),
			route     : "",
			client    : ""
		};

		if ( threadClassifier.isAsyncThread() ) {
			return snapshot;
		}

		try {
			if ( hasColdBoxContext() ) {
				var event      = coldbox.getRequestService().getContext();
				var route      = event.getCurrentRoutedUrl();
				snapshot.route = toString( route.len() ? route : event.getCurrentEvent() ).left( 200 );
			} else if ( cgi.request_method.trim().len() ) {
				// Use path_info if present, otherwise script_name. On IIS they can be the same path.
				var path       = cgi.path_info.trim().len() ? cgi.path_info : cgi.script_name;
				snapshot.route = toString( path ).left( 200 );
			}
		} catch ( any e ) {
		}

		try {
			// Behind a proxy, remote_addr is the proxy; the forwarded header's
			// first entry is the real client.
			var forwarded   = cgi.http_x_forwarded_for;
			snapshot.client = toString( forwarded.len() ? forwarded.listFirst().trim() : cgi.remote_addr ).left( 200 );
		} catch ( any e ) {
		}

		return snapshot;
	}

	/**
	 * dispatch
	 *
	 * Sends one payload without allowing notifier failures into the request.
	 * Returns false when the notifier threw. A notifier reports a failed
	 * delivery by throwing; EmailNotifier throws errorAlerts.DeliveryFailed.
	 * This is the only place a notifier failure is printed.
	 *
	 * @payload The notification payload from PayloadBuilder.
	 */
	private boolean function dispatch( required struct payload ){
		try {
			getNotifier().sendNotification( arguments.payload );
			return true;
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts notifier failed: " & failureText( e ) );
			return false;
		}
	}

	/**
	 * sendDigest
	 *
	 * Builds and sends one digest. A failure is printed and goes no further,
	 * so it cannot stop the alert sent alongside it or the next digest.
	 *
	 * @seed The expired window from ThrottleService.
	 */
	private void function sendDigest( required struct seed ){
		try {
			dispatch( payloadBuilder.buildDigest( arguments.seed ) );
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts digest failed: " & failureText( e ) );
		}
	}

	/**
	 * failureText
	 *
	 * Returns an exception's message and detail for System.err, capped so a
	 * stack trace in the detail cannot flood the log.
	 *
	 * @error The caught exception.
	 */
	private string function failureText( required any error ){
		var text = "";
		try {
			text = "#arguments.error.message# #arguments.error.detail#";
		} catch ( any e ) {
		}
		return text.left( variables.MAX_FAILURE_TEXT );
	}

}
