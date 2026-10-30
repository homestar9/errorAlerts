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

				// The runner is a web request. Specs that need an async thread change this stub.
				threadStub = createStub();
				threadStub.$( "isAsyncThread", false );

				capture = prepareMock( new errorAlerts.models.CaptureService() );
				capture.$property( propertyName = "settings", mock = settings );
				capture.$property( propertyName = "signatureService", mock = signatureStub );
				capture.$property( propertyName = "throttleService", mock = throttleStub );
				capture.$property( propertyName = "payloadBuilder", mock = builderStub );
				capture.$property( propertyName = "threadClassifier", mock = threadStub );
				capture.setNotifier( notifierStub );

				// The timeout extension depends on the engine. Specs that test it choose one.
				capture.$( "currentEngine", "" );
			} );

			it( "notifies once on a SEND verdict", function(){
				capture.capture( newLogEvent() );
				expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
			} );

			describe( "capture() result", function(){
				/* captureException() records an exception as reported only when
				 * capture() returns true. Skips are decisions and return true; only a
				 * failed alert returns false, so onError() can retry it. */

				it( "returns true when the alert is sent", function(){
					expect( capture.capture( newLogEvent() ) ).toBeTrue();
				} );

				it( "returns true for a SUPPRESS verdict", function(){
					throttleStub.$( "record", { action : "SUPPRESS", occurrence : 4, expiredDigest : {} } );
					expect( capture.capture( newLogEvent() ) ).toBeTrue();
				} );

				it( "returns true when the module is disabled", function(){
					settings.enabled = false;
					expect( capture.capture( newLogEvent() ) ).toBeTrue();
				} );

				it( "returns true for an ignored category", function(){
					expect( capture.capture( newLogEvent( category = "cbmailservices.mail" ) ) ).toBeTrue();
				} );

				it( "returns true for a duplicate framework log", function(){
					var result = capture.capture(
						newLogEvent(
							message   = "Error calling quotes.index: boom detail",
							extraInfo = newRestHandlerExtraInfo()
						)
					);
					expect( result ).toBeTrue();
				} );

				it( "returns false when the notifier throws", function(){
					notifierStub.$(
						method         = "sendNotification",
						throwException = true,
						throwType      = "errorAlerts.DeliveryFailed",
						throwMessage   = "email delivery failed"
					);
					expect( capture.capture( newLogEvent() ) ).toBeFalse();
				} );

				it( "returns false when the alert cannot be built", function(){
					builderStub.$(
						method         = "build",
						throwException = true,
						throwType      = "BuildDown",
						throwMessage   = "build exploded"
					);
					expect( capture.capture( newLogEvent() ) ).toBeFalse();
				} );

				it( "still sends the alert and returns true when the digest cannot be built", function(){
					throttleStub.$( "record", {
						action        : "SEND",
						occurrence    : 1,
						expiredDigest : { signature : "sig-1", suppressedCount : 9 }
					} );
					builderStub.$(
						method         = "buildDigest",
						throwException = true,
						throwType      = "DigestDown",
						throwMessage   = "digest exploded"
					);

					expect( capture.capture( newLogEvent() ) ).toBeTrue();
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1, "the alert still went out" );
				} );

				it( "returns true when only the digest delivery fails", function(){
					throttleStub.$( "record", {
						action        : "SEND",
						occurrence    : 1,
						expiredDigest : { signature : "sig-1", suppressedCount : 9 }
					} );
					notifierStub.$( "sendNotification" ).$callback( function( payload ){
						if ( arguments.payload.type == "digest" ) {
							throw( type = "errorAlerts.DeliveryFailed", message = "digest delivery failed" );
						}
					} );

					expect( capture.capture( newLogEvent() ) ).toBeTrue();
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 2 );
				} );
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

			describe( "ignoreMessagePatterns", function(){
				it( "skips a log message that matches a pattern, ignoring case", function(){
					settings.ignoreMessagePatterns = [ "clientabortexception" ];
					capture.capture( newLogEvent( message = "Unhandled exception: ClientAbortException: java.io.IOException" ) );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
					expect( throttleStub.$count( "record" ) ).toBe( 0, "ignored events never reach the throttle" );
				} );

				it( "skips a logged error whose exception message matches", function(){
					settings.ignoreMessagePatterns = [ "Fixture explosion" ];
					capture.capture( newLogEvent( message = "Order could not be saved", extraInfo = newExceptionInfo() ) );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				} );

				it( "skips a logged error whose exception detail matches", function(){
					settings.ignoreMessagePatterns = [ "^Deliberate test" ];
					capture.capture( newLogEvent( message = "Order could not be saved", extraInfo = newExceptionInfo() ) );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				} );

				it( "still sends when no pattern matches", function(){
					settings.ignoreMessagePatterns = [ "ClientAbortException", "connection was aborted" ];
					capture.capture( newLogEvent( extraInfo = newExceptionInfo() ) );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
				} );

				it( "skips an invalid pattern and still checks the others", function(){
					settings.ignoreMessagePatterns = [ "([unclosed", "Something" ];
					expect( function(){
						capture.capture( newLogEvent( message = "Something failed" ) );
					} ).notToThrow();
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0, "the valid pattern still matches" );
				} );

				it( "sends when the only pattern is invalid", function(){
					settings.ignoreMessagePatterns = [ "([unclosed" ];
					capture.capture( newLogEvent() );
					expect( notifierStub.$count( "sendNotification" ) ).toBe( 1, "a bad pattern ignores nothing" );
				} );

				it( "applies to exceptions reported through captureException", function(){
					structDelete( request, "_errorAlertsReported" );
					structDelete( request, "_errorAlertsCapturing" );
					settings.ignoreMessagePatterns = [ "An established connection was aborted" ];
					var info = newExceptionInfo();
					info.message = "An established connection was aborted by the software in your host machine";

					capture.captureException( info );

					expect( notifierStub.$count( "sendNotification" ) ).toBe( 0 );
				} );
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

			it( "leaves the snapshot route and client blank in a scheduled task thread", function(){
				makePublic( capture, "buildSnapshot" );
				threadStub.$( "isAsyncThread", true );

				// A task thread carries a copy of the request that created it.
				var eventStub = createStub();
				eventStub.$( "getCurrentRoutedUrl", "blog/july-contractor-of-the-month/" );
				eventStub.$( "getCurrentEvent", "blog.show" );
				var requestServiceStub = createStub();
				requestServiceStub.$( "contextExists", true );
				requestServiceStub.$( "getContext", eventStub );
				var controllerStub = createStub();
				controllerStub.$( "getRequestService", requestServiceStub );
				capture.$property( propertyName = "coldbox", mock = controllerStub );

				var snapshot = capture.buildSnapshot( newLogEvent() );

				expect( snapshot.route ).toBe( "", "the copied route is not the task's route" );
				expect( snapshot.client ).toBe( "", "the copied client address is not the task's client" );
				expect( snapshot.message ).toBe( "Something failed", "the digest fields still fill in" );
				expect( requestServiceStub.$count( "getContext" ) ).toBe( 0, "the copied request context is never read" );
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
					structDelete( request, "_errorAlertsTimeoutExtended" );
				} );

				afterEach( function(){
					structDelete( request, "_errorAlertsTimeoutExtended" );
				} );

				describe( "retry after a failed alert", function(){
					it( "sends the same exception again after its first alert failed", function(){
						var state = { calls : 0 };
						notifierStub.$( "sendNotification" ).$callback( function(){
							state.calls++;
							if ( state.calls == 1 ) {
								throw( type = "errorAlerts.DeliveryFailed", message = "email delivery failed" );
							}
						} );

						capture.captureException( newExceptionInfo() );
						capture.captureException( newExceptionInfo() );
						capture.captureException( newExceptionInfo() );

						expect( state.calls ).toBe( 2, "the retry sent, and the call after that success was dropped" );
					} );

					it( "retries after a notifier failure of any type", function(){
						var state = { calls : 0 };
						notifierStub.$( "sendNotification" ).$callback( function(){
							state.calls++;
							if ( state.calls == 1 ) {
								throw( type = "NotifierDown", message = "custom notifier exploded" );
							}
						} );

						capture.captureException( newExceptionInfo() );
						capture.captureException( newExceptionInfo() );

						expect( state.calls ).toBe( 2 );
					} );

					it( "records the exception as reported whenever capture() returns true", function(){
						// capture() also returns true for deliberate skips such as an ignored type.
						capture.$( "capture", true );

						capture.captureException( newExceptionInfo() );
						capture.captureException( newExceptionInfo() );

						expect( capture.$count( "capture" ) ).toBe( 1 );
					} );
				} );

				describe( "request timeout extension on Adobe", function(){
					/* Adobe throws the timeout again at every later checking tag once the
					 * request is past its limit, so captureException() extends the limit
					 * first. Its limit is measured from the start of the request. */

					beforeEach( function(){
						capture.$( "currentEngine", "adobe" );
						capture.$( "adobeRequestTimeoutSeconds", 2 );
						capture.$( "applyRequestTimeout" );
					} );

					it( "does nothing while the request is within its limit", function(){
						capture.$( "adobeRequestTimedOut", false );

						capture.captureException( newExceptionInfo() );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 0 );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );

					it( "adds the extension to the current limit", function(){
						capture.$( "adobeRequestTimedOut" ).$results( true, false );

						capture.captureException( newExceptionInfo() );

						var applied = capture.$callLog().applyRequestTimeout;
						expect( applied.len() ).toBe( 1 );
						expect( applied[ 1 ][ 1 ] ).toBe( 62 );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );

					it( "doubles the limit until the request is within it, then extends once more", function(){
						// One long query can run far past the limit, so limit + 60 can already be over.
						capture.$( "adobeRequestTimedOut" ).$results( true, true, true, false );

						capture.captureException( newExceptionInfo() );

						var applied  = capture.$callLog().applyRequestTimeout;
						var expected = [ 62, 124, 248, 308 ];
						expect( applied.len() ).toBe( expected.len() );
						for ( var i = 1; i <= expected.len(); i++ ) {
							expect( applied[ i ][ 1 ] ).toBe( expected[ i ], "limit #i#" );
						}
					} );

					it( "stops doubling after the probe limit", function(){
						capture.$( "adobeRequestTimedOut", true );

						capture.captureException( newExceptionInfo() );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 22, "the first limit, 20 doublings, and the final extension" );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );

					it( "extends a request at most once", function(){
						capture.$( "adobeRequestTimedOut" ).$results( true, false );

						capture.captureException( newExceptionInfo( line = 1 ) );
						capture.captureException( newExceptionInfo( line = 2 ) );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 1 );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 2 );
					} );

					it( "does nothing when the extension is below one second", function(){
						capture.$( "adobeRequestTimedOut", true );

						settings.timeoutExtensionSeconds = 0;
						capture.captureException( newExceptionInfo( line = 1 ) );
						settings.timeoutExtensionSeconds = 0.5;
						capture.captureException( newExceptionInfo( line = 2 ) );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 0, "a limit of 0 would remove the time limit" );
						expect( capture.$count( "adobeRequestTimedOut" ) ).toBe( 0, "the cheap checks run first" );
					} );

					it( "does nothing on BoxLang, which does not enforce the limit", function(){
						capture.$( "currentEngine", "boxlang" );
						capture.$( "adobeRequestTimedOut", true );
						capture.$( "luceeElapsedMs", 999999 );

						capture.captureException( newExceptionInfo() );

						expect( capture.$count( "adobeRequestTimedOut" ) ).toBe( 0 );
						expect( capture.$count( "luceeElapsedMs" ) ).toBe( 0 );
						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 0 );
					} );

					it( "still sends the alert when the extension fails", function(){
						capture.$(
							method         = "adobeRequestTimedOut",
							throwException = true,
							throwType      = "MonitorDown",
							throwMessage   = "no request monitor"
						);

						capture.captureException( newExceptionInfo() );

						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );

					it( "does not extend for an abort", function(){
						capture.$( "adobeRequestTimedOut", true );

						capture.captureException( newAbortInfo( "coldfusion.runtime.AbortException" ) );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 0 );
					} );
				} );

				describe( "request timeout extension on Lucee", function(){
					/* Lucee's controller thread stops a timed-out request, then stops it
					 * again on a later pass while onError() is still reporting the first
					 * timeout. That second stop is an abort no catch can handle. */

					beforeEach( function(){
						capture.$( "currentEngine", "lucee" );
						capture.$( "luceeRequestTimeoutMs", 2000 );
						capture.$( "applyRequestTimeout" );
						capture.$( "adobeRequestTimedOut", true );
					} );

					it( "does nothing while the request is within its limit", function(){
						capture.$( "luceeElapsedMs", 1500 );

						capture.captureException( newExceptionInfo() );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 0 );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );

					it( "sets the limit to the elapsed time plus the extension", function(){
						// One long call ran far past the 2-second limit.
						capture.$( "luceeElapsedMs", 95200 );

						capture.captureException( newExceptionInfo() );

						var applied = capture.$callLog().applyRequestTimeout;
						expect( applied.len() ).toBe( 1 );
						expect( applied[ 1 ][ 1 ] ).toBe( 156, "96 seconds elapsed, rounded up, plus 60" );
						expect( capture.$count( "adobeRequestTimedOut" ) ).toBe( 0, "Adobe's monitor is never touched" );
						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );

					it( "extends a request at most once", function(){
						capture.$( "luceeElapsedMs", 2100 );

						capture.captureException( newExceptionInfo( line = 1 ) );
						capture.captureException( newExceptionInfo( line = 2 ) );

						expect( capture.$count( "applyRequestTimeout" ) ).toBe( 1 );
					} );

					it( "still sends the alert when the page context cannot be read", function(){
						capture.$(
							method         = "luceeElapsedMs",
							throwException = true,
							throwType      = "NoPageContext",
							throwMessage   = "no page context"
						);

						capture.captureException( newExceptionInfo() );

						expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
					} );
				} );

				it( "builds the unhandled-exception LogEvent and captures it", function(){
					capture.$( "capture", true );
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
					capture.$( "capture", true );
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
					capture.$( "capture", true );
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

			it( "flushDigests still sends the other digests when one cannot be built", function(){
				throttleStub.$( "flushExpired", [ { signature : "a" }, { signature : "b" } ] );
				builderStub.$( "buildDigest" ).$callback( function( seed ){
					if ( arguments.seed.signature == "a" ) {
						throw( type = "DigestDown", message = "digest exploded" );
					}
					return { type : "digest" };
				} );

				capture.flushDigests();

				expect( notifierStub.$count( "sendNotification" ) ).toBe( 1 );
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
