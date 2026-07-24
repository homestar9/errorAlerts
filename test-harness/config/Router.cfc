/**
 * Configures routes for the test harness.
 */
component {

	/**
	 * configure
	 *
	 * Adds the default handler and optional action route.
	 */
	function configure(){
		setFullRewrites( true );
		route( ":handler/:action?" ).end();
	}

}
