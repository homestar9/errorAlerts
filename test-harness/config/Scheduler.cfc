/**
 * Harness Scheduler
 *
 * Auto-registered by ColdBox as `appScheduler@coldbox`.
 *
 * Runs one task that fails only when armFailure() asks it to. ColdBox's
 * BaseProxy copies the request that started the application into the task's
 * executor thread, so the alert shows whether errorAlerts ignores that copy.
 */
component {

	/**
	 * configure
	 *
	 * Registers the task that fails on request.
	 *
	 * ColdBox also logs a task failure under coldbox.system.web.tasks, but the
	 * harness LogBox config sends coldbox.system only to the console, as ColdBox's
	 * app template does. onFailure() reports it through a harness logger instead,
	 * still inside the task's thread.
	 */
	function configure(){
		// The task thread and the request that arms it both use this counter.
		variables.pendingFailures = createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init( 0 );
		variables.taskLog         = getInstance( dsl = "logbox:logger:harness.tasks" );

		task( "harnessFailingTask" )
			.call( function(){
				if ( variables.pendingFailures.get() > 0 ) {
					variables.pendingFailures.decrementAndGet();
					throw(
						type    = "Harness.Task.Failed",
						message = "Harness scheduled task failed in its executor thread",
						detail  = "Armed from the harness."
					);
				}
			} )
			.onFailure( function( task, exception ){
				variables.taskLog.error(
					"Scheduled task harnessFailingTask failed: #arguments.exception.message#",
					arguments.exception
				);
			} )
			.every( 1, "seconds" );
	}

	/**
	 * armFailure
	 *
	 * Makes the next runs of harnessFailingTask throw. The task's onFailure()
	 * handler logs each failure as an ERROR, which errorAlerts emails.
	 *
	 * @count How many runs should fail.
	 */
	function armFailure( numeric count = 1 ){
		variables.pendingFailures.addAndGet( arguments.count );
		return this;
	}

}
