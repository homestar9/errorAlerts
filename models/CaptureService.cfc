/**
 * CaptureService
 *
 * Filters and throttles captured log events before sending notifications.
 * Internal failures go to System.err. This keeps them out of the request and
 * prevents another LogBox event.
 *
 * captureException() is the public entry point for unhandled exceptions. The
 * interceptor uses it for ColdBox requests. Code outside ColdBox, such as an
 * Application.cfc onError() method in a legacy folder of the same application,
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

		// Limit the per-request dedupe registry so a looping onError cannot grow it.
		variables.MAX_REPORTED_PER_REQUEST = 50;

		// Matches the abort pseudo-exception type on every supported engine.
		variables.ABORT_TYPE_PATTERN = "(^|\.)Abort(Exception)?$";

		return this;
	}

	/**
	 * capture
	 *
	 * Checks, throttles, and sends one log event.
	 * Also sends a digest when this event closes an expired throttle window.
	 *
	 * The enabled check runs here as well as at module load. WireBox can create
	 * this service when the module declined to register its appender and
	 * interceptor, for example under a development() override, and a direct
	 * caller must not send alerts in that state.
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
	 * Reports one unhandled exception through the normal capture pipeline.
	 * This is the public entry point for Application.cfc onError() methods and
	 * for the module's own interceptor. It never throws, because it runs inside
	 * error handling.
	 *
	 * Adobe wraps an exception thrown inside an Application.cfc event method in
	 * an EventHandlerException. The wrapper is removed so the email, the
	 * signature, and the dedupe all see the real exception. Abort and relocate
	 * pseudo-exceptions are ignored because they are not errors.
	 *
	 * One exception is reported once per request. An exception handler that
	 * rethrows the original exception into onError() cannot send a second email.
	 * The request flag prevents an exception during capture from calling this
	 * method again.
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
	 * Reloads the CFML mappings that ColdBox modules declare.
	 * Lucee and BoxLang keep mappings added at runtime for one request only, so
	 * ColdBox reloads them at the start of every request. An onError() that runs
	 * before that point, for example after onRequestStart() threw, has no
	 * `cbmailservices` mapping. The first mail build would then fail, and WireBox
	 * drops a mapping it cannot build, which stops every later alert until a
	 * reinit. Adobe keeps mappings for the whole application, so the call is a
	 * no-op there. A failure here is ignored; capture still runs.
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
	 * Converts an exception to the LogEvent the capture pipeline expects.
	 * The message format and the category are part of every error signature.
	 * Changing either one restarts every throttle window.
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
	 * Returns the real exception from an Adobe EventHandlerException wrapper.
	 * Adobe wraps an exception thrown inside onRequest() or onRequestStart()
	 * before it reaches onError(). Only the wrapper is unwrapped. Other Adobe
	 * exceptions also carry a rootCause, so that key alone is not a reason to
	 * unwrap. Returns the original value when there is nothing to unwrap.
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
	 * Checks whether the exception is an engine abort or relocate signal.
	 * Adobe can pass coldfusion.runtime.AbortException to onError() after a
	 * location() or abort inside onRequestStart(). Lucee and BoxLang handle
	 * aborts separately, so the check is defensive there. The cause is checked
	 * as well because a wrapper can carry the abort.
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
	 * Returns a hash that identifies one exception within one request.
	 * The raw type, message, detail, and top frame are used without the
	 * normalization that SignatureService applies, so this check stays
	 * independent of throttle grouping.
	 *
	 * @exception The cfcatch struct or exception object to fingerprint.
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
	 * Returns "template:line" for the first stack frame, or an empty string.
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
	 * Reads one simple field from an exception as text, or returns an empty
	 * string. A Java exception can hold a null message, and reading it directly
	 * throws on some engines. Reading through this method cannot lose an alert.
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
	 * @value The value to test, any type.
	 */
	private boolean function isExceptionLike( required any value ){
		return isObject( arguments.value ) || isStruct( arguments.value );
	}

	/**
	 * hasColdBoxContext
	 *
	 * Checks whether ColdBox routed the current request.
	 * getContext() creates a context when none exists, so it is never called
	 * before this check. A context with no event name was created by a direct
	 * WireBox call from code outside ColdBox and does not count. Keep this
	 * method in step with the copy in PayloadBuilder.
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
	 * or many requests. A page outside ColdBox uses its path as the route. A
	 * failure while reading either value leaves it blank.
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
				// On IIS path_info can repeat script_name, so use one or the other.
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
