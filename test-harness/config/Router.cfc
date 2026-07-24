/**
 * Harness router: conventions only.
 */
component {

	/**
	 * Configures the default convention route.
	 */
	function configure(){
		setFullRewrites( true );
		route( ":handler/:action?" ).end();
	}

}
