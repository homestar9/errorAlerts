/**
 * CaptureService
 *
 * Filters and throttles captured log events before sending notifications.
 * Internal failures go to System.err. This keeps them out of the request and
 * prevents another LogBox event.
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
		return this;
	}

	/**
	 * capture
	 *
	 * Checks, throttles, and sends one log event.
	 * Also sends a digest when this event closes an expired throttle window.
	 *
	 * @logEvent The LogBox LogEvent to process.
	 */
	void function capture( required any logEvent ){
		try {
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
	 * buildSnapshot
	 *
	 * Returns the event details needed for a later digest.
	 * The route and client address help show whether failures came from one page
	 * or many requests. A missing request context leaves those fields blank.
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
			var event      = coldbox.getRequestService().getContext();
			var route      = event.getCurrentRoutedUrl();
			snapshot.route = toString( route.len() ? route : event.getCurrentEvent() ).left( 200 );
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
