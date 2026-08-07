/**
 * CaptureService
 *
 * Processes captured log events and sends approved notifications.
 * Failures go to System.err so they cannot break the request or create another
 * LogBox event.
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
	 * Checks whether this log event is ColdBox's RestHandler logging an
	 * exception that it announces as onException on the very next line. The
	 * module's interceptor captures that announcement, so without this check a
	 * REST application receives two emails for one exception.
	 *
	 * The logged copy is the one dropped, because the announced copy is better.
	 * RestHandler passes { _stacktrace, httpData } as extraInfo. That struct has
	 * no tagContext, so SignatureService.topFrame() and applicationFrame() both
	 * return an empty string, PayloadBuilder renders no stack trace and no code
	 * snippet, and FrameClassifier never runs. The interceptor passes the real
	 * cfcatch, which has all of that.
	 *
	 * The message prefix is matched on purpose. RestHandler.onError() logs the
	 * same { _stacktrace, httpData } shape but does NOT announce onException, so
	 * matching on the struct shape alone would drop those alerts with nothing
	 * left to report them. If ColdBox changes this message text, the check stops
	 * matching and the duplicate email returns, which is noticed right away. It
	 * cannot cause a lost alert.
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

		/* findNoCase() == 1 rather than left( 14 ) because it reads as "starts
		 * with" and does not repeat a length that would have to change with the
		 * text. This is a readability choice, not an engine workaround: Adobe
		 * ColdFusion 2023 and 2025, Lucee 5, and BoxLang all return the whole
		 * string when left() is asked for more characters than it holds. */
		return arguments.logEvent.getMessage().findNoCase( "Error calling " ) == 1;
	}

	/**
	 * buildSnapshot
	 *
	 * Returns the event fields needed to create a later digest, plus the route
	 * and client address of this occurrence. ThrottleService keeps a small
	 * distinct-value sample of those two across the window, so the digest can
	 * say "3 routes from 1 client IP" - the difference between a crawler and a
	 * broken page. Each read is wrapped so a missing request context only
	 * leaves the field blank.
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
