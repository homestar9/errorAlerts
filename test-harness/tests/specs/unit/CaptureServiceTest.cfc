/**
 * Tests CaptureService filtering, throttling results, digests, and failures.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run(){
		describe( "CaptureService", function(){
			beforeEach( function(){
				settings = defaultSettings();

				notifierStub = createStub();
				notifierStub.$( "sendNotification" );

				signatureStub = createStub();
				signatureStub.$( "compute", "sig-1" );

				throttleStub = createStub();
				throttleStub.$( "record", { action : "SEND", occurrence : 1, expiredDigest : {} } );

				builderStub = createStub();
				builderStub.$( "build", { type : "error" } );
				builderStub.$( "buildDigest", { type : "digest" } );

				capture = prepareMock( new errorAlerts.models.CaptureService() );
				capture.$property( propertyName = "settings", mock = settings );
				capture.$property( propertyName = "signatureService", mock = signatureStub );
				capture.$property( propertyName = "throttleService", mock = throttleStub );
				capture.$property( propertyName = "payloadBuilder", mock = builderStub );
				capture.setNotifier( notifierStub );
			} );

			it( "notifies once on a SEND verdict", function(){
				capture.capture( newLogEvent() );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
			} );

			it( "stays silent on a SUPPRESS verdict", function(){
				throttleStub.$( "record", { action : "SUPPRESS", occurrence : 4, expiredDigest : {} } );
				capture.capture( newLogEvent() );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
			} );

			it( "flushes an expired window's digest alongside the new alert", function(){
				throttleStub.$( "record", {
					action        : "SEND",
					occurrence    : 1,
					expiredDigest : { signature : "sig-1", suppressedCount : 9 }
				} );
				capture.capture( newLogEvent() );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 2, "digest plus fresh alert" );
			} );

			it( "skips categories on the ignore list by prefix", function(){
				capture.capture( newLogEvent( category = "cbmailservices.mail" ) );
				capture.capture( newLogEvent( category = "coldbox.system.Bootstrap" ) );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				expect( throttleStub.$count( "record" ) ).toBe( 0, "ignored events never reach the throttle" );
			} );

			it( "does not skip categories that merely contain an ignored prefix mid-string", function(){
				capture.capture( newLogEvent( category = "app.cbmailservices.wrapper" ) );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
			} );

			it( "skips exception types on the ignore list", function(){
				settings.ignoreExceptionTypes = [ "HarnessBoom" ];
				capture.capture( newLogEvent( extraInfo = newExceptionInfo() ) );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
			} );

			describe( "duplicate framework logs", function(){
				/* ColdBox's RestHandler.onAnyOtherException() logs the exception
				 * and then announces onException on the next line. Both reach
				 * the module, so the logged copy is dropped. RestHandler.onError()
				 * logs the same shape but announces nothing, so its copy must be
				 * kept or that alert disappears completely. */

				it( "skips the log that RestHandler.onAnyOtherException also announces", function(){
					capture.capture(
						newLogEvent(
							message   = "Error calling quotes.index: boom detail",
							extraInfo = newRestHandlerExtraInfo(),
							category  = "modules_app.api.handlers.Quotes"
						)
					);
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
					expect( throttleStub.$count( "record" ) ).toBe( 0, "the event never reaches the throttle" );
				} );

				it( "keeps the RestHandler.onError log, which announces nothing", function(){
					capture.capture(
						newLogEvent(
							message   = "Error in base handler (index): boom detail",
							extraInfo = newRestHandlerExtraInfo(),
							category  = "modules_app.api.handlers.Quotes"
						)
					);
					expect( notifierStub.$count( "sendNotification" ) ).toBe(
						1,
						"nothing else reports this exception"
					);
				} );

				it( "keeps an 'Error calling' log that carries a real tagContext", function(){
					capture.capture(
						newLogEvent( message = "Error calling quotes.index: boom", extraInfo = newExceptionInfo() )
					);
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "keeps the duplicate when suppressDuplicateFrameworkLogs is off", function(){
					settings.suppressDuplicateFrameworkLogs = false;
					capture.capture(
						newLogEvent(
							message   = "Error calling quotes.index: boom detail",
							extraInfo = newRestHandlerExtraInfo()
						)
					);
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1, "the escape hatch works" );
				} );

				it( "keeps a log whose extraInfo has no httpData", function(){
					capture.capture(
						newLogEvent(
							message   = "Error calling quotes.index: boom detail",
							extraInfo = { "_stacktrace" : "java.lang.Exception: boom" }
						)
					);
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1, "not the RestHandler shape" );
				} );

				it( "handles a message shorter than the matched prefix", function(){
					expect( function(){
						capture.capture( newLogEvent( message = "Boom", extraInfo = newRestHandlerExtraInfo() ) );
					} ).notToThrow( message = "a message shorter than the prefix must not break the check" );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "handles a simple extraInfo value", function(){
					expect( function(){
						capture.capture( newLogEvent( message = "Error calling quotes.index: boom", extraInfo = "just a string" ) );
					} ).notToThrow();
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );
			} );

			it( "snapshots the route and client for digest sampling", function(){
				makePublic( capture, "buildSnapshot" );

				var eventStub = createStub();
				eventStub.$( "getCurrentRoutedUrl", "blog/hello/" );
				eventStub.$( "getCurrentEvent", "posts.show" );
				var requestServiceStub = createStub();
				requestServiceStub.$( "getContext", eventStub );
				var controllerStub = createStub();
				controllerStub.$( "getRequestService", requestServiceStub );
				capture.$property( propertyName = "coldbox", mock = controllerStub );

				var snapshot = capture.buildSnapshot( newLogEvent() );

				expect( snapshot.route ).toBe( "blog/hello/" );
				expect( snapshot ).toHaveKey( "client", "the client address is read from the CGI scope" );
			} );

			it( "leaves the snapshot route blank when there is no request context", function(){
				makePublic( capture, "buildSnapshot" );

				var broken = createStub();
				broken.$(
					method         = "getRequestService",
					throwException = true,
					throwType      = "NoContext",
					throwMessage   = "no request here"
				);
				capture.$property( propertyName = "coldbox", mock = broken );

				var snapshot = capture.buildSnapshot( newLogEvent() );

				expect( snapshot.route ).toBe( "" );
				expect( snapshot.message ).toBe( "Something failed", "the digest fields still fill in" );
			} );

			it( "flushDigests notifies one digest per expired seed", function(){
				throttleStub.$( "flushExpired", [ { signature : "a" }, { signature : "b" } ] );
				capture.flushDigests();
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 2 );
			} );

			it( "resolves the configured notifier through WireBox (the swap seam)", function(){
				settings.notifier = "MyCustomNotifier@myModule";
				var wireboxStub   = createStub();
				wireboxStub.$( "getInstance", notifierStub );

				var fresh = prepareMock( new errorAlerts.models.CaptureService() );
				fresh.$property( propertyName = "settings", mock = settings );
				fresh.$property( propertyName = "wirebox", mock = wireboxStub );

				expect( fresh.getNotifier() ).toBe( notifierStub );
				expect( wireboxStub.$callLog().getInstance[ 1 ][ 1 ] ).toBe( "MyCustomNotifier@myModule" );
			} );

			it( "swallows notifier failures instead of throwing into the request", function(){
				var brokenNotifier = createStub();
				brokenNotifier.$(
					method         = "sendNotification",
					throwException = true,
					throwType      = "NotifierDown",
					throwMessage   = "delivery exploded"
				);
				capture.setNotifier( brokenNotifier );

				expect( function(){
					capture.capture( newLogEvent() );
				} ).notToThrow();
			} );

			it( "swallows pipeline failures instead of throwing into the request", function(){
				signatureStub.$(
					method         = "compute",
					throwException = true,
					throwType      = "HashDown",
					throwMessage   = "hashing exploded"
				);

				expect( function(){
					capture.capture( newLogEvent() );
				} ).notToThrow();
			} );
		} );
	}

}
