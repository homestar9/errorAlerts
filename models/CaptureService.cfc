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
	 * @logEvent The LogBox LogEvent to process.
	 */
	void function capture( required any logEvent ){
		try {
			if ( !settings.enabled ) {
				return;
			}

			if ( isIgnored( arguments.logEvent ) ) {
				return;
			}

			if ( isDuplicateFrameworkLog( arguments.logEvent ) ) {
				return;
			}

			var signature = signatureService.compute( arguments.logEvent );
			var verdict   = throttleService.record(
				signature = signature,
				snapshot  = buildSnapshot( arguments.logEvent )
			);

			if ( !verdict.expiredDigest.isEmpty() ) {
				dispatch( payloadBuilder.buildDigest( verdict.expiredDigest ) );
			}

			if ( verdict.action == "SEND" ) {
				dispatch( payloadBuilder.build( arguments.logEvent, signature, verdict.occurrence ) );
			}
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts capture failed: #e.message# #e.detail#" );
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
	 * reported by the interceptor, causing onError() to run. The request flag
	 * prevents this method from running again while a capture is in progress.
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

			ensureModuleMappings();

			if ( !request.keyExists( "_errorAlertsReported" ) ) {
				request._errorAlertsReported = {};
			}
			var key = requestFingerprint( target );
			if ( request._errorAlertsReported.keyExists( key ) ) {
				return;
			}
			if ( structCount( request._errorAlertsReported ) < variables.MAX_REPORTED_PER_REQUEST ) {
				request._errorAlertsReported[ key ] = true;
			}

			request._errorAlertsCapturing = true;
			try {
				capture( newUnhandledEvent( target ) );
			} finally {
				request.delete( "_errorAlertsCapturing" );
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
				dispatch( payloadBuilder.buildDigest( seed ) );
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
	 * Checks the category prefix and exception type ignore lists.
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
	 *
	 * @payload The notification payload from PayloadBuilder.
	 */
	private void function dispatch( required struct payload ){
		try {
			getNotifier().sendNotification( arguments.payload );
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts notifier failed: #e.message# #e.detail#" );
		}
	}

}
