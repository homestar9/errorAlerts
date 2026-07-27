/**
 * Api
 *
 * A REST handler that fails, so the module's behavior can be compared against
 * the plain handler in Trigger.cfc.
 *
 * RestHandler catches exceptions in its own onError(), which logs at ERROR under
 * this handler's category. That reaches the module's appender, and ColdBox also
 * announces onException, so /api/boom produces two alert emails where a plain
 * handler produces one. See docs/test-harness.md.
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
	 * Catches its own failure and logs it, which is what a REST handler usually
	 * does. This one alerts through the appender and still returns clean JSON.
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
