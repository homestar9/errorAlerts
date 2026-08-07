/**
 * errorAlerts Scheduler
 *
 * Auto-registered by ColdBox as `cbScheduler@errorAlerts`.
 */
component {

	/**
	 * configure
	 *
	 * Schedules regular checks for expired throttle windows.
	 * A quiet window needs this task because no new error will close the window.
	 */
	function configure(){
		// Use 60 seconds when the module settings are unavailable.
		var flushSeconds = 60;
		try {
			flushSeconds = getInstance( dsl = "coldbox:moduleSettings:errorAlerts" ).digestFlushSeconds;
		} catch ( any e ) {
		}

		task( "errorAlerts-digest-flush" )
			.call( function(){
				getInstance( "CaptureService@errorAlerts" ).flushDigests();
			} )
			.every( flushSeconds, "seconds" )
			.delay( flushSeconds, "seconds" )
			.onFailure( function( task, exception ){
				// Logging this failure would call the module's appender again.
			} );
	}

}
