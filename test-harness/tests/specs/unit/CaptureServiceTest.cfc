/**
 * Tests CaptureService filtering, throttling results, digests, and failures.
 */
component extends="tests.resources.BaseUnitSpec" {

	/**
	 * run
	 *
	 * Defines CaptureService unit tests.
	 */
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
				/* RestHandler reports some errors twice, but onError() only logs once.
				 * Drop duplicates without losing the single onError report. */

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
				requestServiceStub.$( "contextExists", true );
				requestServiceStub.$( "getContext", eventStub );
				var controllerStub = createStub();
				controllerStub.$( "getRequestService", requestServiceStub );
				capture.$property( propertyName = "coldbox", mock = controllerStub );

				var snapshot = capture.buildSnapshot( newLogEvent() );

				expect( snapshot.route ).toBe( "blog/hello/" );
				expect( snapshot ).toHaveKey( "client", "the client address is read from the CGI scope" );
			} );

			it( "uses the request path as the snapshot route outside ColdBox", function(){
				makePublic( capture, "buildSnapshot" );

				var requestServiceStub = createStub();
				requestServiceStub.$( "contextExists", false );
				// Register this mock so $count() can return zero instead of "never mocked".
				requestServiceStub.$( "getContext", createStub() );
				var controllerStub = createStub();
				controllerStub.$( "getRequestService", requestServiceStub );
				capture.$property( propertyName = "coldbox", mock = controllerStub );

				var snapshot = capture.buildSnapshot( newLogEvent() );
				// Adobe cannot call a method on (condition ? a : b). Store the path first.
				var path     = cgi.path_info.trim().len() ? cgi.path_info : cgi.script_name;
				var expected = left( path, 200 );

				expect( snapshot.route ).toBe( expected, "the snapshot route contains the page path" );
				expect( requestServiceStub.$count( "getContext" ) ).toBe( 0, "building the snapshot does not create a request context" );
			} );

			it( "sends nothing when the module is disabled", function(){
				settings.enabled = false;
				capture.capture( newLogEvent() );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				expect( throttleStub.$count( "record" ) ).toBe( 0, "a disabled module does not record errors for throttling" );
			} );

			describe( "captureException", function(){
				beforeEach( function(){
					// Every spec shares one runner request, so clear the per-request state.
					structDelete( request, "_errorAlertsReported" );
					structDelete( request, "_errorAlertsCapturing" );
				} );

				it( "builds the unhandled-exception LogEvent and captures it", function(){
					capture.$( "capture" );
					var info = newExceptionInfo();

					capture.captureException( info );

					expect( capture.$count( "capture" ) ).toBe( 1 );
					var logEvent = capture.$callLog().capture[ 1 ][ 1 ];
					expect( logEvent.getMessage() ).toBe( "Unhandled exception: Fixture explosion Deliberate test exception" );
					expect( logEvent.getSeverity() ).toBe( 1 );
					expect( logEvent.getCategory() ).toBe( "UnhandledException" );
					expect( logEvent.getExtraInfo() ).toBe( info );
				} );

				it( "sends nothing when the module is disabled", function(){
					settings.enabled = false;
					capture.captureException( newExceptionInfo() );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				} );

				it( "reloads the module mappings before capturing", function(){
					/* On Lucee and BoxLang, onError() has no module mappings if it runs
					 * before ColdBox starts handling the request. Without a reload, the
					 * first mail build fails and later alerts fail until the application
					 * is reinitialized. */
					var moduleServiceStub = createStub();
					moduleServiceStub.$( "loadMappings" );
					var controllerStub = createStub();
					controllerStub.$( "getModuleService", moduleServiceStub );
					capture.$property( propertyName = "coldbox", mock = controllerStub );

					capture.captureException( newExceptionInfo() );

					expect( moduleServiceStub.$count( "loadMappings" ) ).toBe( 1 );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "still captures when the mappings cannot be reloaded", function(){
					var broken = createStub();
					broken.$(
						method         = "getModuleService",
						throwException = true,
						throwType      = "NoModules",
						throwMessage   = "module service unavailable"
					);
					capture.$property( propertyName = "coldbox", mock = broken );

					capture.captureException( newExceptionInfo() );

					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "reports one exception once per request", function(){
					capture.captureException( newExceptionInfo() );
					capture.captureException( newExceptionInfo() );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1, "the second report is dropped" );
				} );

				it( "still reports exceptions that differ only by line", function(){
					capture.captureException( newExceptionInfo( line = 1 ) );
					capture.captureException( newExceptionInfo( line = 2 ) );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 2 );
				} );

				it( "does nothing while another capture is in progress", function(){
					request._errorAlertsCapturing = true;
					try {
						capture.captureException( newExceptionInfo() );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
						expect( request.keyExists( "_errorAlertsCapturing" ) ).toBeTrue( "the flag stays set until the capture already in progress finishes" );
					} finally {
						structDelete( request, "_errorAlertsCapturing" );
					}
				} );

				it( "ignores exception types used for aborts and redirects on every engine", function(){
					capture.captureException( newAbortInfo( "coldfusion.runtime.AbortException" ) );
					capture.captureException( newAbortInfo( "lucee.runtime.exp.Abort" ) );
					capture.captureException( newAbortInfo( "ortus.boxlang.runtime.types.exceptions.AbortException" ) );
					capture.captureException( newAbortInfo( "abort" ) );
					capture.captureException( {
						type      : "coldfusion.runtime.EventHandlerException",
						message   : "Event Handler Exception.",
						detail    : "",
						rootCause : newAbortInfo( "coldfusion.runtime.AbortException" )
					} );
					capture.captureException( {
						type    : "java.lang.RuntimeException",
						message : "wrapped abort",
						detail  : "",
						cause   : newAbortInfo( "lucee.runtime.exp.Abort" )
					} );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				} );

				it( "reports errors whose type contains abort but is not an abort type", function(){
					capture.captureException( newAbortInfo( "MyApp.AbortedOrder" ) );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "unwraps Adobe's EventHandlerException wrapper", function(){
					capture.$( "capture" );
					var real = newExceptionInfo();

					capture.captureException( {
						type      : "coldfusion.runtime.EventHandlerException",
						message   : "Event Handler Exception.",
						detail    : "",
						rootCause : real
					} );

					var logEvent = capture.$callLog().capture[ 1 ][ 1 ];
					expect( logEvent.getExtraInfo() ).toBe( real, "capture() receives the original exception" );
					expect( logEvent.getMessage() ).toInclude( "Fixture explosion" );
				} );

				it( "keeps an ordinary exception unchanged when it has a rootCause", function(){
					capture.$( "capture" );
					var info      = newExceptionInfo();
					info.type     = "Database";
					info.rootCause = { type : "java.sql.SQLException", message : "driver detail" };

					capture.captureException( info );

					expect( capture.$callLog().capture[ 1 ][ 1 ].getExtraInfo().type ).toBe( "Database" );
				} );

				it( "reports an exception with no message key without throwing", function(){
					expect( function(){
						capture.captureException( { type : "Weird" } );
					} ).notToThrow();
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "accepts a simple value without throwing", function(){
					expect( function(){
						capture.captureException( "just text" );
					} ).notToThrow();
				} );
			} );

			it( "leaves the snapshot route blank when the request service fails", function(){
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

	/**
	 * newAbortInfo
	 *
	 * Builds a test exception struct for an abort passed to onError().
	 *
	 * @type The engine's abort exception type name.
	 */
	private struct function newAbortInfo( required string type ){
		return {
			type       : arguments.type,
			message    : "",
			detail     : "",
			stacktrace : "",
			tagContext : []
		};
	}

}
