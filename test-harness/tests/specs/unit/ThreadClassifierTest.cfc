/**
 * Tests how ThreadClassifier separates ColdBox async threads from requests and cfthread.
 */
component extends="tests.resources.BaseUnitSpec" {

	/**
	 * run
	 *
	 * Defines ThreadClassifier unit tests.
	 */
	function run(){
		describe( "ThreadClassifier", function(){
			beforeEach( function(){
				// Every engine signal starts off, so each spec turns on only the one it tests.
				classifier = prepareMock( new errorAlerts.models.ThreadClassifier() );
				classifier.$( "engineName", "adobe" );
				classifier.$( "isCfThread", false );
				classifier.$( "adobeAsyncFlag", false );
				classifier.$( "luceeDummyContext", false );
				classifier.$( "boxLangThreadContext", false );
				classifier.$( "currentThreadName", "XNIO-1 task-3" );
				classifier.$( "liveStackTemplates", [] );
			} );

			describe( "isAsyncThread", function(){
				it( "is true for an Adobe thread carrying ColdBox's async flag", function(){
					classifier.$( "adobeAsyncFlag", true );
					expect( classifier.isAsyncThread() ).toBeTrue();
				} );

				it( "is false for an Adobe cfthread that inherited the async flag", function(){
					// FusionContext.clone() copies the flag into a cfthread started inside a task.
					classifier.$( "adobeAsyncFlag", true );
					classifier.$( "isCfThread", true );
					classifier.$( "currentThreadName", "cfthread-4" );
					expect( classifier.isAsyncThread() ).toBeFalse();
				} );

				it( "is true for a Lucee dummy page context", function(){
					classifier.$( "engineName", "lucee" );
					classifier.$( "luceeDummyContext", true );
					expect( classifier.isAsyncThread() ).toBeTrue();
				} );

				it( "is true for a BoxLang ThreadBoxContext", function(){
					classifier.$( "engineName", "boxlang" );
					classifier.$( "boxLangThreadContext", true );
					expect( classifier.isAsyncThread() ).toBeTrue();
				} );

				it( "only reads the signal of the current engine", function(){
					classifier.$( "engineName", "lucee" );
					classifier.$( "adobeAsyncFlag", true );
					classifier.$( "boxLangThreadContext", true );
					expect( classifier.isAsyncThread() ).toBeFalse();
				} );

				it( "falls back to the JDK executor thread names", function(){
					for ( var name in [ "pool-1-thread-1", "pool-67-thread-12", "ForkJoinPool.commonPool-worker-3", "ForkJoinPool-2-worker-5" ] ) {
						classifier.$( "currentThreadName", name );
						expect( classifier.isAsyncThread() ).toBeTrue( name );
					}
				} );

				it( "is false for request thread names without an engine signal", function(){
					var names = [
						"XNIO-1 task-3",
						"ajp-nio-127.0.0.1-8022-exec-4",
						"http-nio-8500-exec-1",
						"qtp1234-56",
						"my-pool-1-thread-1",
						""
					];
					for ( var name in names ) {
						classifier.$( "currentThreadName", name );
						expect( classifier.isAsyncThread() ).toBeFalse( name );
					}
				} );

				it( "returns false instead of throwing when a check fails", function(){
					classifier.$(
						method         = "adobeAsyncFlag",
						throwException = true,
						throwType      = "EngineChanged",
						throwMessage   = "no such method"
					);
					expect( classifier.isAsyncThread() ).toBeFalse();
				} );
			} );

			describe( "hasScheduledTaskFrame", function(){
				it( "finds a scheduled task frame on the live stack", function(){
					classifier.$( "liveStackTemplates", [
						"C:\sites\app\coldbox\system\web\tasks\ColdBoxScheduledTask.cfc",
						"C:\sites\app\coldbox\system\async\tasks\ScheduledTask.cfc"
					] );
					expect( classifier.hasScheduledTaskFrame() ).toBeTrue();
				} );

				it( "finds a scheduled task frame in exception frames", function(){
					var frames = [
						{ template : "/var/www/handlers/Cleanup.cfc", line : 12 },
						{ template : "/opt/libs/coldbox-8/system/async/tasks/ScheduledTask.cfc", line : 734 }
					];
					expect( classifier.hasScheduledTaskFrame( frames ) ).toBeTrue( "the install folder does not matter" );
				} );

				it( "is false when neither the stack nor the frames hold a task", function(){
					classifier.$( "liveStackTemplates", [ "/app/coldbox/system/async/cbproxies/models/BaseProxy.cfc" ] );
					var frames = [ { template : "/app/models/ScheduledTaskReport.cfc", line : 3 } ];
					expect( classifier.hasScheduledTaskFrame( frames ) ).toBeFalse();
				} );
			} );

			it( "reports the current thread name", function(){
				classifier.$( "currentThreadName", "pool-3-thread-2" );
				expect( classifier.threadName() ).toBe( "pool-3-thread-2" );
			} );

			it( "does not classify the runner's own request thread as async on this engine", function(){
				// No stubs: every real engine check runs against a real web request.
				var live = new errorAlerts.models.ThreadClassifier();
				expect( live.isAsyncThread() ).toBeFalse( "thread #live.threadName()#" );
				expect( live.threadName() ).notToBeEmpty();
			} );
		} );
	}

}
