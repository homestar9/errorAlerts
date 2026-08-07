/**
 * Tests appender, interceptor, scheduler, and activation registration.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	/**
	 * run
	 *
	 * Defines registration and settings integration tests.
	 */
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

		describe( "nested settings defaults", function(){
			beforeEach( function(){
				moduleConfig = prepareMock( new errorAlerts.ModuleConfig() );
				makePublic( moduleConfig, "applyNestedDefaults" );
			} );

			it( "fills the keys a partial includeScopes override dropped", function(){
				/* ColdBox replaces the complete nested struct. Module startup must
				 * restore the missing includeScopes defaults. */
				var settings = { includeScopes : { session : true } };
				moduleConfig.applyNestedDefaults( settings );

				expect( settings.includeScopes.session ).toBeTrue( "the override must win" );
				expect( settings.includeScopes.rc ).toBeTrue();
				expect( settings.includeScopes.cgi ).toBeTrue();
				expect( settings.includeScopes.extraInfo ).toBeTrue();
			} );

			it( "fills the keys a partial throttle override dropped", function(){
				var settings = { throttle : { windowSeconds : 60 } };
				moduleConfig.applyNestedDefaults( settings );

				expect( settings.throttle.windowSeconds ).toBe( 60, "the override must win" );
				expect( settings.throttle.maxPerWindow ).toBe( 3 );
				expect( settings.throttle.maxTrackedSignatures ).toBe( 500 );
			} );

			it( "adds both structs when the application configured neither", function(){
				var settings = {};
				moduleConfig.applyNestedDefaults( settings );

				expect( settings.throttle ).toHaveKey( "maxPerWindow" );
				expect( settings.includeScopes ).toHaveKey( "rc" );
			} );

			it( "replaces a nested setting that is not a struct at all", function(){
				var settings = { includeScopes : true };
				moduleConfig.applyNestedDefaults( settings );

				expect( settings.includeScopes ).toBeStruct();
				expect( settings.includeScopes.rc ).toBeTrue();
			} );

			it( "leaves a complete override exactly as configured", function(){
				var settings = {
					includeScopes : { rc : false, cgi : false, extraInfo : false, session : true },
					throttle      : { maxPerWindow : 9, windowSeconds : 30, maxTrackedSignatures : 10 }
				};
				moduleConfig.applyNestedDefaults( settings );

				expect( settings.includeScopes.rc ).toBeFalse();
				expect( settings.includeScopes.session ).toBeTrue();
				expect( settings.throttle.maxPerWindow ).toBe( 9 );
				expect( settings.throttle.windowSeconds ).toBe( 30 );
			} );

			it( "repairs the settings struct the running module actually uses", function(){
				// Confirm that WireBox receives the repaired settings struct.
				var live = getController().getSetting( "moduleSettings" ).errorAlerts;

				for ( var key in [ "rc", "cgi", "extraInfo", "session" ] ) {
					expect( live.includeScopes ).toHaveKey( key );
				}
				for ( var key in [ "maxPerWindow", "windowSeconds", "maxTrackedSignatures" ] ) {
					expect( live.throttle ).toHaveKey( key );
				}

				expect( getInstance( "PayloadBuilder@errorAlerts" ).getSettings().includeScopes ).toHaveKey(
					"rc",
					"the injected copy must be the repaired one"
				);
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
