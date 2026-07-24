/**
 * errorAlerts Scheduler
 * Auto-registered by ColdBox as `cbScheduler@errorAlerts`.
 */
component {

	/**
	 * Schedules the digest flush. Without it, a digest for a burst of suppressed
	 * errors would wait for the NEXT error to roll its window over. On a quiet
	 * site that could be hours away, so this sweep runs on a timer instead.
	 *
	 * The task swallows its own failures on purpose: nothing in this module may
	 * log at ERROR, because that would feed the very appender this task powers.
	 * When the module is inactive the throttle state is empty and the flush is
	 * a no-op, so the task is safe to register unconditionally.
	 */
	function configure(){
		// Read the cadence from settings, falling back to 60s if unavailable.
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
				// Swallowed on purpose: see the configure() docblock.
			} );
	}

}
