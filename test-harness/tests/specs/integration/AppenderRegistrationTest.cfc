/**
 * Integration tests for module wiring: the appender lands on the root logger,
 * the interceptor and scheduler register, and the isActive() gating logic
 * makes the right call for every configuration shape.
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
					enabled      : true,
					environments : [],
					to           : "dave@example.com",
					notifier     : "EmailNotifier@errorAlerts"
				};
			} );

			it( "is inactive when disabled", function(){
				settings.enabled = false;
				expect( moduleConfig.isActive( settings, "production" ) ).toBeFalse();
			} );

			it( "skips development by default but runs everywhere else", function(){
				expect( moduleConfig.isActive( settings, "development" ) ).toBeFalse();
				expect( moduleConfig.isActive( settings, "production" ) ).toBeTrue();
				expect( moduleConfig.isActive( settings, "staging" ) ).toBeTrue();
			} );

			it( "honors an explicit environments allow-list", function(){
				settings.environments = [ "staging" ];
				expect( moduleConfig.isActive( settings, "staging" ) ).toBeTrue();
				expect( moduleConfig.isActive( settings, "production" ) ).toBeFalse();
				expect( moduleConfig.isActive( settings, "development" ) ).toBeFalse();
			} );

			it( "is inactive with the shipped EmailNotifier and a blank `to`", function(){
				settings.to = "";
				expect( moduleConfig.isActive( settings, "production" ) ).toBeFalse();
			} );

			it( "allows a blank `to` when a custom notifier is configured", function(){
				settings.to       = "";
				settings.notifier = "SentryNotifier@myModule";
				expect( moduleConfig.isActive( settings, "production" ) ).toBeTrue();
			} );
		} );
	}

}
