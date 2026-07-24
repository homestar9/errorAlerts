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
	 * Without this task, a quiet window cannot produce a digest until the next
	 * matching error arrives.
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
				// Do not log this failure because an error log would call the
				// module's appender again.
			} );
	}

}
