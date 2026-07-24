/**
 * UnhandledExceptionCapture
 *
 * Receives unhandled exceptions from ColdBox's onException interception point.
 * ColdBox does not log the exception when an application has a custom
 * exceptionHandler, so ErrorAlertAppender cannot capture it in that case.
 *
 * Without a custom handler, ColdBox also logs the exception under
 * coldbox.system.Bootstrap. The default ignore list skips that event to prevent
 * a second alert for the same exception.
 */
component extends="coldbox.system.Interceptor" {

	property name="captureService" inject="CaptureService@errorAlerts";

	/**
	 * onException
	 *
	 * Converts an unhandled exception to a LogEvent and captures it.
	 * The request flag must be checked before capture. Moving it later would
	 * allow an exception during capture to enter this method again.
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
			// Adobe ColdFusion cfcatch values can be objects instead of structs.
			// Use structKeyExists() so both forms can be read safely.
			var message   = "Unhandled exception: "
			& ( structKeyExists( exception, "message" ) ? exception.message : "" )
			& " "
			& ( structKeyExists( exception, "detail" ) ? exception.detail : "" );

			captureService.capture(
				new coldbox.system.logging.LogEvent(
					message   = message,
					severity  = 1, // LogBox ERROR
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
