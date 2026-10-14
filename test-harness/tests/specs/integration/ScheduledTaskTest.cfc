/**
 * Tests alerts raised inside a real ColdBox scheduled task thread and inside cfthread.
 *
 * ColdBox's BaseProxy copies the request that started the application into each
 * task thread. These specs prove the alert ignores that copy on the running engine.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	// The harness task's onFailure() handler logs this message (test-harness/config/Scheduler.cfc).
	variables.TASK_ALERT = "Scheduled task harnessFailingTask failed";

	/**
	 * run
	 *
	 * Defines scheduled task and background thread alert tests.
	 */
	function run(){
		describe( "Alerts from scheduled tasks and threads", function(){
			beforeEach( function(){
				resetThrottle();
				clearMailbox();
				resetRequestState();
			} );

			it( "labels a scheduled task failure and leaves out the copied request", function(){
				getInstance( "appScheduler@coldbox" ).armFailure();

				var alerts = waitForMail( TASK_ALERT );

				expect( alerts.len() ).toBe( 1, "the task failure was emailed within the time limit" );
				var body = alerts[ 1 ].body;
				// The renderer HTML-encodes the parentheses around the thread name.
				expect( body ).toMatch(
					"scheduled task (\(|&##x28;|&##40;)pool-[0-9]+-thread-[0-9]+",
					"the context row names the task thread"
				);
				expect( body ).toInclude( "not a ColdBox request" );
				expect( body ).notToInclude( "web request", "the copied CGI scope does not make it a web request" );
				for ( var label in [ "url", "method", "templatePath", "host", "remoteAddr", "userAgent", "event", "route", "elapsed" ] ) {
					expect( body ).notToInclude( ">#label#</td>", "the #label# row would describe the copied request" );
				}
				expect( body ).notToInclude( "Request collection (rc)", "the copied rc is left out" );
				expect( body ).toInclude( ">machine</td>" );
				expect( body ).toInclude( ">memory</td>" );
				expect( body ).toInclude( ">origin</td>" );
			} );

			it( "keeps alerting when the same task fails again", function(){
				var scheduler = getInstance( "appScheduler@coldbox" );

				scheduler.armFailure();
				expect( waitForMail( TASK_ALERT ).len() ).toBe( 1 );

				scheduler.armFailure();
				expect( waitForMail( TASK_ALERT, 2 ).len() ).toBe(
					2,
					"a second failure still alerts, so no request-scope flag from the first run blocks it"
				);
			} );

			it( "keeps the existing classification for cfthread", function(){
				var jobLogger  = getController().getLogBox().getLogger( "integrationThread" );
				var threadName = "eaSpecThread#createUUID().replace( "-", "", "all" )#";

				thread name=threadName jobLogger=jobLogger {
					attributes.jobLogger.error( "cfthread alert from the integration spec" );
				}
				cfthread( action = "join", name = threadName, timeout = 5000 );

				var alerts = waitForMail( "cfthread alert from the integration spec" );

				expect( alerts.len() ).toBe( 1 );
				expect( alerts[ 1 ].body ).notToInclude( "scheduled task" );
				expect( alerts[ 1 ].body ).notToInclude( "async thread" );
			} );
		} );
	}

	/**
	 * waitForMail
	 *
	 * Polls the in-memory mailbox until enough emails contain the text, or the
	 * time limit passes. A task runs on its own thread, so its email arrives
	 * after the spec arms it.
	 *
	 * @text      Text the email body must contain.
	 * @count     How many matching emails to wait for.
	 * @timeoutMs How long to wait before returning what has arrived.
	 */
	private array function waitForMail(
		required string text,
		numeric count     = 1,
		numeric timeoutMs = 15000
	){
		var deadline = getTickCount() + arguments.timeoutMs;
		var found    = [];

		while ( true ) {
			found = [];
			for ( var mail in getMailbox() ) {
				if ( mail.body.find( arguments.text ) ) {
					found.append( mail );
				}
			}
			if ( found.len() >= arguments.count || getTickCount() > deadline ) {
				return found;
			}
			sleep( 200 );
		}
	}

}
