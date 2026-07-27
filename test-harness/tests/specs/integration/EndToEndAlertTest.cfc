/**
 * Tests alerts through LogBox, throttling, rendering, and the in-memory mailer.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	function run(){
		describe( "End-to-end alerts", function(){
			beforeEach( function(){
				resetThrottle();
				clearMailbox();
			} );

			it( "emails a manual logger.error() call", function(){
				getController().getLogBox().getLogger( "integrationTest" ).error( "e2e boom" );

				var mailbox = getMailbox();
				expect( mailbox.len() ).toBe( 1 );
				expect( mailbox[ 1 ].to ).toBe( "alerts@example.com" );
				expect( mailbox[ 1 ].from ).toBe( "harness@example.com" );
				expect( mailbox[ 1 ].subject ).toInclude( "[Harness]" );
				expect( mailbox[ 1 ].subject ).toInclude( "ERROR" );
				expect( mailbox[ 1 ].body ).toInclude( "e2e boom" );
				expect( mailbox[ 1 ].body ).notToInclude( "<style" );
			} );

			it( "sends the first 3 of a burst and suppresses the rest", function(){
				var logger = getController().getLogBox().getLogger( "integrationTest" );
				for ( var i = 1; i <= 5; i++ ) {
					logger.error( "burst boom" );
				}
				expect( getMailbox().len() ).toBe( 3 );
			} );

			it( "does not email INFO or WARN events", function(){
				var logger = getController().getLogBox().getLogger( "integrationTest" );
				logger.info( "just info" );
				logger.warn( "just a warning" );
				expect( getMailbox() ).toBeEmpty();
			} );

			it( "emails unhandled exceptions via the onException interception", function(){
				getController()
					.getInterceptorService()
					.announce( "onException", { exception : newExceptionInfo( "interceptor boom" ) } );

				var mailbox = getMailbox();
				expect( mailbox.len() ).toBe( 1 );
				expect( mailbox[ 1 ].subject ).toInclude( "Unhandled exception" );
				expect( mailbox[ 1 ].body ).toInclude( "interceptor boom" );
				expect( mailbox[ 1 ].body ).toInclude( "Main.cfc" );
				expect( mailbox[ 1 ].body ).toInclude( "origin", "the request section always names the origin" );
			} );

			it( "ignores categories on the ignore list", function(){
				getController().getLogBox().getLogger( "cbmailservices.queue" ).error( "mail down" );
				getController().getLogBox().getLogger( "coldbox.system.Bootstrap" ).error( "already intercepted" );
				expect( getMailbox() ).toBeEmpty();
			} );

			it( "delivers a digest after the window closes", function(){
				// Shorten the shared throttle window for this test, then restore
				// it so later tests keep the default value.
				var settings = getInstance( "CaptureService@errorAlerts" ).getSettings();
				var original = settings.throttle.windowSeconds;

				try {
					settings.throttle.windowSeconds = 1;

					var logger = getController().getLogBox().getLogger( "integrationTest" );
					for ( var i = 1; i <= 5; i++ ) {
						logger.error( "digest boom" );
					}
					expect( getMailbox().len() ).toBe( 3, "the burst itself sends 3" );

					sleep( 1100 );
					getInstance( "CaptureService@errorAlerts" ).flushDigests();

					var mailbox = getMailbox();
					expect( mailbox.len() ).toBe( 4, "the flush adds exactly one digest" );
					expect( mailbox[ 4 ].subject ).toInclude( "DIGEST" );
					expect( mailbox[ 4 ].subject ).toInclude( "2 more times" );
					expect( mailbox[ 4 ].body ).toInclude( "Total occurrences" );
					expect( mailbox[ 4 ].body ).toInclude( "1 second", "a sub-minute window must not read as 0 minutes" );
				} finally {
					settings.throttle.windowSeconds = original;
				}
			} );
		} );
	}

}
