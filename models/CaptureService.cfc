/**
 * CaptureService
 *
 * The pipeline orchestrator: takes a log event from the appender or the
 * unhandled-exception interceptor, applies the ignore lists, computes the
 * signature, asks the throttle for a verdict, and dispatches payloads to the
 * configured notifier. Every internal failure is swallowed to System.err;
 * nothing in this pipeline may throw into the failing request or log at ERROR
 * through LogBox (either would loop back into the appender).
 */
component singleton accessors="true" {

	// Injected properties
	property name="settings"         inject="coldbox:moduleSettings:errorAlerts";
	property name="signatureService" inject="SignatureService@errorAlerts";
	property name="throttleService"  inject="ThrottleService@errorAlerts";
	property name="payloadBuilder"   inject="PayloadBuilder@errorAlerts";
	property name="wirebox"          inject="wirebox";

	/**
	 * Constructor. Grabs the System handle used for stderr failure notes.
	 */
	function init(){
		variables.system = createObject( "java", "java.lang.System" );
		return this;
	}

	/**
	 * Runs the full pipeline for one log event: ignore lists, signature,
	 * throttle verdict, then notification. A window that expired on this very
	 * occurrence also flushes its digest here.
	 *
	 * @logEvent The LogBox LogEvent to process.
	 */
	void function capture( required any logEvent ){
		try {
			if ( isIgnored( arguments.logEvent ) ) {
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
	 * Flushes digests for every expired throttle window. Called by the module's
	 * scheduled task so a burst that went quiet still produces its digest.
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
	 * Replaces the notifier at runtime. Used by tests, and by hosts that want
	 * to swap delivery without a reinit.
	 *
	 * @notifier Any object implementing INotifier's sendNotification().
	 */
	any function setNotifier( required any notifier ){
		variables.notifier = arguments.notifier;
		return this;
	}

	/**
	 * Resolves the configured notifier (settings.notifier is a WireBox ID)
	 * lazily and caches it. This indirection is the seam that lets a host swap
	 * EmailNotifier for a Sentry (or any other) notifier via config alone.
	 */
	any function getNotifier(){
		if ( !variables.keyExists( "notifier" ) ) {
			variables.notifier = wirebox.getInstance( settings.notifier );
		}
		return variables.notifier;
	}

	/**
	 * Applies the ignore lists: category PREFIX matches from
	 * settings.ignoreCategories, then exception `type` matches from
	 * settings.ignoreExceptionTypes when the event carries an exception.
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
			// cfcatch objects are struct-like but not true structs on Adobe CF,
			// so key access uses structKeyExists() instead of the member form.
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
	 * Builds the compact snapshot the throttle keeps per window, so a digest
	 * can describe the burst without holding the whole log event in memory.
	 *
	 * @logEvent The LogBox LogEvent being recorded.
	 */
	private struct function buildSnapshot( required any logEvent ){
		return {
			message   : arguments.logEvent.getMessage().left( 500 ),
			category  : arguments.logEvent.getCategory(),
			severity  : arguments.logEvent.getSeverity(),
			timestamp : arguments.logEvent.getTimestamp()
		};
	}

	/**
	 * Hands one payload to the notifier inside its own try/catch, so a broken
	 * notifier can never take the pipeline (or the request) down with it.
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
