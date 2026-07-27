/**
 * ReportBuilder
 *
 * Builds a deliberately deep call stack before failing. The module's
 * `stackFrames` setting defaults to 10, so an alert from here should list ten
 * frames and drop the rest.
 */
component singleton {

	/**
	 * build
	 *
	 * Recurses `depth` times and then throws.
	 *
	 * @depth How many frames to add before failing.
	 */
	function build( numeric depth = 25 ){
		return descend( arguments.depth );
	}

	/**
	 * descend
	 *
	 * Calls itself until the counter runs out, then throws.
	 *
	 * @remaining Frames left to add.
	 */
	private function descend( required numeric remaining ){
		if ( arguments.remaining <= 0 ) {
			throw(
				type    = "Harness.Report.BuildFailed",
				message = "Report generation failed at the bottom of the call stack",
				detail  = "This exception was thrown 25 frames below the handler so the stackFrames limit can be checked."
			);
		}
		return descend( arguments.remaining - 1 );
	}

}
