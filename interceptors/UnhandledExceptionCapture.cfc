/**
 * UnhandledExceptionCapture
 *
 * Listens to ColdBox's `onException` interception point, which Bootstrap
 * announces for EVERY unhandled exception. This is the only reliable hook when
 * a host defines its own `exceptionHandler` setting: in that case ColdBox runs
 * the handler and never logs the exception through LogBox, so the module's
 * appender alone would miss it.
 *
 * Hosts WITHOUT a custom exceptionHandler get the same exception logged by
 * Bootstrap under the "coldbox.system.Bootstrap" category as well; that
 * category sits in the default ignoreCategories list precisely so those hosts
 * are not alerted twice for one crash.
 */
component extends="coldbox.system.Interceptor" {

	property name="captureService" inject="CaptureService@errorAlerts";

	/**
	 * Wraps the unhandled exception in a LogBox LogEvent and feeds it through
	 * the same capture pipeline the appender uses, so throttling and rendering
	 * treat both sources identically. Shares the appender's request-scope
	 * re-entrancy flag: an exception thrown DURING capture must not re-enter.
	 *
	 * @event  The current request context.
	 * @data   The interception data. `data.exception` holds the cfcatch struct.
	 * @buffer The interception buffer (unused).
	 * @rc     The request collection (unused).
	 * @prc    The private request collection (unused).
	 */
	function onException( event, data, buffer, rc, prc ){
		if ( request.keyExists( "_errorAlertsCapturing" ) ) {
			return;
		}

		if ( !arguments.data.keyExists( "exception" ) ) {
			return;
		}

		request._errorAlertsCapturing = true;
		try {
			var exception = arguments.data.exception;
			// cfcatch objects are struct-like but not true structs on Adobe CF,
			// so key access uses structKeyExists() instead of the member form.
			var message   = "Unhandled exception: "
			& ( structKeyExists( exception, "message" ) ? exception.message : "" )
			& " "
			& ( structKeyExists( exception, "detail" ) ? exception.detail : "" );

			captureService.capture(
				new coldbox.system.logging.LogEvent(
					message   = message,
					severity  = 1, // ERROR
					extraInfo = exception,
					category  = "UnhandledException"
				)
			);
		} catch ( any e ) {
			createObject( "java", "java.lang.System" ).err.println(
				"errorAlerts interceptor failed: #e.message# #e.detail#"
			);
		} finally {
			request.delete( "_errorAlertsCapturing" );
		}
	}

}
