/**
 * Tests throttle limits, expiration, digests, memory limits, and locking.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run(){
		describe( "ThrottleService", function(){
			beforeEach( function(){
				service = prepareMock( new errorAlerts.models.ThrottleService() );
				service.$property( propertyName = "settings", mock = defaultSettings() );
				snapshot = {
					message   : "boom",
					category  : "tests.fixture",
					severity  : 1,
					timestamp : now()
				};
			} );

			it( "sends the first N occurrences of a signature", function(){
				for ( var i = 1; i <= 3; i++ ) {
					var verdict = service.record( "sig-a", snapshot );
					expect( verdict.action ).toBe( "SEND", "occurrence #i# should send" );
					expect( verdict.occurrence ).toBe( i );
				}
			} );

			it( "suppresses everything after the first N", function(){
				for ( var i = 1; i <= 3; i++ ) {
					service.record( "sig-a", snapshot );
				}
				var fourth = service.record( "sig-a", snapshot );
				var fifth  = service.record( "sig-a", snapshot );
				expect( fourth.action ).toBe( "SUPPRESS" );
				expect( fourth.occurrence ).toBe( 4 );
				expect( fifth.action ).toBe( "SUPPRESS" );
				expect( fifth.occurrence ).toBe( 5 );
			} );

			it( "throttles signatures independently", function(){
				for ( var i = 1; i <= 4; i++ ) {
					service.record( "sig-a", snapshot );
				}
				var other = service.record( "sig-b", snapshot );
				expect( other.action ).toBe( "SEND" );
				expect( other.occurrence ).toBe( 1 );
			} );

			it( "rolls an expired window into a digest seed on the next occurrence", function(){
				var settings                    = defaultSettings();
				settings.throttle.maxPerWindow  = 1;
				settings.throttle.windowSeconds = 1;
				service.$property( propertyName = "settings", mock = settings );

				service.record( "sig-a", snapshot ); // Send and start the window.
				service.record( "sig-a", snapshot ); // Suppress this occurrence.
				service.record( "sig-a", snapshot ); // Suppress this occurrence.
				sleep( 1100 );

				var verdict = service.record( "sig-a", snapshot );
				expect( verdict.action ).toBe( "SEND", "a fresh window should open after expiry" );
				expect( verdict.occurrence ).toBe( 1 );
				expect( verdict.expiredDigest ).notToBeEmpty();
				expect( verdict.expiredDigest.totalCount ).toBe( 3 );
				expect( verdict.expiredDigest.sentCount ).toBe( 1 );
				expect( verdict.expiredDigest.suppressedCount ).toBe( 2 );
				expect( verdict.expiredDigest.signature ).toBe( "sig-a" );
			} );

			it( "flushExpired returns digests only for windows that suppressed something", function(){
				var settings                    = defaultSettings();
				settings.throttle.maxPerWindow  = 1;
				settings.throttle.windowSeconds = 1;
				service.$property( propertyName = "settings", mock = settings );

				service.record( "sig-suppressed", snapshot );
				service.record( "sig-suppressed", snapshot ); // Suppress one occurrence.
				service.record( "sig-clean", snapshot );      // Send every occurrence.
				sleep( 1100 );

				var seeds = service.flushExpired();
				expect( seeds.len() ).toBe( 1 );
				expect( seeds[ 1 ].signature ).toBe( "sig-suppressed" );
				expect( seeds[ 1 ].suppressedCount ).toBe( 1 );

				// The first flush removed both expired windows.
				expect( service.flushExpired() ).toBeEmpty();
			} );

			it( "fails open when the signature cap is reached", function(){
				var settings                           = defaultSettings();
				settings.throttle.maxTrackedSignatures = 2;
				service.$property( propertyName = "settings", mock = settings );

				service.record( "sig-1", snapshot );
				service.record( "sig-2", snapshot );

				// The full registry cannot track sig-3, so it sends without state.
				expect( service.record( "sig-3", snapshot ).action ).toBe( "SEND" );
				expect( service.record( "sig-3", snapshot ).action ).toBe( "SEND", "untracked signatures always send" );
			} );

			it( "reset clears all state", function(){
				for ( var i = 1; i <= 4; i++ ) {
					service.record( "sig-a", snapshot );
				}
				service.reset();
				var verdict = service.record( "sig-a", snapshot );
				expect( verdict.action ).toBe( "SEND" );
				expect( verdict.occurrence ).toBe( 1 );
			} );

			it( "does not lose counts under concurrent recording", function(){
				/* Read shared values from the spec variables scope. Adobe
				 * ColdFusion deep-copies thread attributes, which would give each
				 * thread a different service. Track completion in `done` because
				 * BoxLang does not join a thread from inside this closure. */
				done = {};
				for ( var t = 1; t <= 4; t++ ) {
					thread name="throttleSmoke#t##createUUID()#" {
						for ( var i = 1; i <= 50; i++ ) {
							service.record( "sig-threaded", snapshot );
						}
						done[ createUUID() ] = true;
					}
				}

				var deadline = getTickCount() + 10000;
				while ( done.count() < 4 && getTickCount() < deadline ) {
					sleep( 25 );
				}
				expect( done.count() ).toBe( 4, "all worker threads should finish within 10s" );

				var verdict = service.record( "sig-threaded", snapshot );
				expect( verdict.occurrence ).toBe( 201, "4 threads x 50 records + this one should count 201" );
			} );
		} );
	}

}
