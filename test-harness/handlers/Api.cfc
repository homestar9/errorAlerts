/**
 * Api
 *
 * Provides REST failures for comparing with the plain Trigger handler.
 *
 * RestHandler logs an action error and then announces onException. Both reports
 * reach the module. The module drops the logged copy because only the
 * announcement has the tagContext needed for stack frames and source code.
 * ApiFault.cfc covers the path that logs without an announcement.
 */
component extends="coldbox.system.RestHandler" {

	/**
	 * index
	 *
	 * Returns a working response so the handler can be checked before failing it.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function index( event, rc, prc ){
		prc.response.setData( { "status" : "ok", "handler" : "Api" } );
	}

	/**
	 * boom
	 *
	 * Throws inside a REST action.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function boom( event, rc, prc ){
		throw(
			type    = "Harness.Api.Boom",
			message = "REST endpoint failed while building the response",
			detail  = "Thrown inside a handler that extends coldbox.system.RestHandler."
		);
	}

	/**
	 * logged
	 *
	 * Catches and logs a failure, then returns a valid JSON response.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function logged( event, rc, prc ){
		try {
			throw(
				type    = "Harness.Api.UpstreamFailed",
				message = "Upstream inventory call failed",
				detail  = "The REST action caught this itself and logged it."
			);
		} catch ( any e ) {
			controller.getLogBox().getLogger( "api.inventory" ).error( "GET /api/logged failed: #e.message#", e );
			prc.response.setError( true ).setStatusCode( 502 ).addMessage( "Upstream failure" );
		}
	}

}
