/**
 * ApiFault
 *
 * A REST handler that fails before its action runs, so the kept alert path can
 * be checked.
 *
 * RestHandler.aroundHandler() catches everything the action throws and sends it
 * to onAnyOtherException(), which logs the exception and then announces
 * onException. The module drops that logged copy, because the announcement
 * produces a better alert. See Api.cfc for that case.
 *
 * An exception thrown in preHandler escapes aroundHandler instead. ColdBox
 * catches it and calls RestHandler.onError(), which logs the same
 * { _stacktrace, httpData } shape but announces nothing. That log is the only
 * report of the failure, so the module must still alert on it. /apiFault/boom
 * exists to prove it does.
 *
 * onError() rethrows instead of logging when ColdBox debugMode is on. The
 * harness leaves debugMode off, so this scenario logs as intended.
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
