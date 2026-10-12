/**
 * UnhandledExceptionCapture
 *
 * Receives unhandled exceptions from ColdBox's onException interception point.
 * A custom exceptionHandler stops ColdBox from logging the exception. This
 * interceptor makes sure ErrorAlertAppender is not the only capture path.
 *
 * Without a custom handler, ColdBox also logs the exception under
 * coldbox.system.Bootstrap. The default ignore list skips that event to prevent
 * a second alert for the same exception.
 *
 * CaptureService.captureException() does the work. It owns the reentrancy
 * flag and the per-request dedupe, so an Application.cfc onError() hook and
 * this interceptor share one path.
 */
component extends="coldbox.system.Interceptor" {

	property name="captureService" inject="CaptureService@errorAlerts";

	/**
	 * onException
	 *
	 * Passes the unhandled exception to CaptureService.
	 *
	 * @event  The current request context.
	 * @data   The interception data. `data.exception` holds the cfcatch struct.
	 * @buffer The interception buffer (unused).
	 * @rc     The request collection (unused).
	 * @prc    The private request collection (unused).
	 */
	function onException( event, data, buffer, rc, prc ){
		if ( !arguments.data.keyExists( "exception" ) ) {
			return;
		}

		try {
			captureService.captureException( arguments.data.exception );
		} catch ( any e ) {
			createObject( "java", "java.lang.System" ).err.println(
				"errorAlerts interceptor failed: #e.message# #e.detail#"
			);
		}
	}

}
