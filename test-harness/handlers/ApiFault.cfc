/**
 * ApiFault
 *
 * Fails before its REST action to test the alert that must be kept.
 *
 * RestHandler logs errors from an action and then announces onException. The
 * module keeps the announcement because it contains better exception data.
 *
 * An error from preHandler reaches RestHandler.onError() instead. onError() logs
 * _stacktrace and httpData but does not announce onException. That log is the
 * only report, so the module must keep it.
 *
 * The harness keeps debugMode off because onError() rethrows in debug mode.
 */
component extends="coldbox.system.RestHandler" {

	/**
	 * preHandler
	 *
	 * Throws before the action runs, which reaches RestHandler.onError().
	 *
	 * @event          The current request context.
	 * @rc             The request collection.
	 * @prc            The private request collection.
	 * @action         The action about to run.
	 * @eventArguments The original event arguments.
	 */
	function preHandler( event, rc, prc, action, eventArguments ){
		throw(
			type    = "Harness.ApiFault.Boom",
			message = "REST request failed before the action ran",
			detail  = "Thrown in preHandler, which reaches RestHandler.onError() rather than onAnyOtherException()."
		);
	}

	/**
	 * boom
	 *
	 * Never runs. preHandler throws first.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function boom( event, rc, prc ){
		prc.response.setData( { "status" : "unreachable" } );
	}

}
