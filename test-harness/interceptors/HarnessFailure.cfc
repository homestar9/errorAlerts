/**
 * HarnessFailure
 *
 * Throws from ColdBox interception points before or after a handler action.
 *
 * The interceptor only throws when rc.harnessFail selects one of its methods.
 *
 * The selected method removes the flag before throwing. ColdBox runs the
 * interception points again for the exceptionHandler event, so leaving the flag
 * in place would create a loop.
 */
component extends="coldbox.system.Interceptor" {

	/**
	 * preProcess
	 *
	 * Throws before ColdBox works out which event to run.
	 *
	 * @event  The current request context.
	 * @data   The interception data (unused).
	 * @buffer The interception buffer (unused).
	 * @rc     The request collection.
	 * @prc    The private request collection (unused).
	 */
	function preProcess( event, data, buffer, rc, prc ){
		if ( arguments.rc.keyExists( "harnessFail" ) && arguments.rc.harnessFail == "preProcess" ) {
			arguments.rc.delete( "harnessFail" );
			throw(
				type    = "Harness.Interceptor.PreProcessFailed",
				message = "Interceptor failed during preProcess",
				detail  = "HarnessFailure threw before ColdBox chose an event."
			);
		}
	}

	/**
	 * preEvent
	 *
	 * Throws just before the handler action runs.
	 *
	 * @event  The current request context.
	 * @data   The interception data (unused).
	 * @buffer The interception buffer (unused).
	 * @rc     The request collection.
	 * @prc    The private request collection (unused).
	 */
	function preEvent( event, data, buffer, rc, prc ){
		if ( arguments.rc.keyExists( "harnessFail" ) && arguments.rc.harnessFail == "preEvent" ) {
			arguments.rc.delete( "harnessFail" );
			throw(
				type    = "Harness.Interceptor.PreEventFailed",
				message = "Interceptor failed during preEvent",
				detail  = "HarnessFailure threw after the event was chosen but before the action ran."
			);
		}
	}

	/**
	 * postEvent
	 *
	 * Throws after the handler action has already finished successfully.
	 *
	 * @event  The current request context.
	 * @data   The interception data (unused).
	 * @buffer The interception buffer (unused).
	 * @rc     The request collection.
	 * @prc    The private request collection (unused).
	 */
	function postEvent( event, data, buffer, rc, prc ){
		if ( arguments.rc.keyExists( "harnessFail" ) && arguments.rc.harnessFail == "postEvent" ) {
			arguments.rc.delete( "harnessFail" );
			throw(
				type    = "Harness.Interceptor.PostEventFailed",
				message = "Interceptor failed during postEvent",
				detail  = "HarnessFailure threw after the handler action had already run."
			);
		}
	}

}
