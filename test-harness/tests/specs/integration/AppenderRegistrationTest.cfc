/**
 * Tests appender, interceptor, scheduler, and activation registration.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	function run(){
		describe( "Module registration", function(){
			it( "registers the appender in the LogBox registry", function(){
				expect( getController().getLogBox().getAppenderRegistry() ).toHaveKey( "errorAlerts" );
			} );

			it( "attaches the appender to the root logger", function(){
				expect( getController().getLogBox().getRootLogger().appenderExists( "errorAlerts" ) ).toBeTrue();
			} );

			it( "registers the appender at FATAL..ERROR only", function(){
				var appender = getController().getLogBox().getAppenderRegistry()[ "errorAlerts" ];
				expect( appender.getLevelMin() ).toBe( 0 );
				expect( appender.getLevelMax() ).toBe( 1 );
			} );

			it( "registers the unhandled-exception interceptor", function(){
				expect( function(){
					getController().getInterceptorService().getInterceptor( "UnhandledExceptionCapture@errorAlerts" );
				} ).notToThrow();
			} );

			it( "registers the digest-flush scheduler", function(){
				expect( getController().getSchedulerService().getSchedulers() ).toHaveKey( "cbScheduler@errorAlerts" );
			} );
		} );

		describe( "isActive() gating", function(){
			beforeEach( function(){
				moduleConfig = prepareMock( new errorAlerts.ModuleConfig() );
				makePublic( moduleConfig, "isActive" );
				settings = {
					enabled  : true,
					to       : "dave@example.com",
					notifier : "EmailNotifier@errorAlerts"
				};
			} );

			it( "is active when enabled and `to` is set", function(){
				expect( moduleConfig.isActive( settings ) ).toBeTrue();
			} );

			it( "is inactive when disabled", function(){
				settings.enabled = false;
				expect( moduleConfig.isActive( settings ) ).toBeFalse();
			} );

			it( "is inactive with the shipped EmailNotifier and a blank `to`", function(){
				settings.to = "";
				expect( moduleConfig.isActive( settings ) ).toBeFalse();
			} );

			it( "allows a blank `to` when a custom notifier is configured", function(){
				settings.to       = "";
				settings.notifier = "SentryNotifier@myModule";
				expect( moduleConfig.isActive( settings ) ).toBeTrue();
			} );
		} );
	}

}
