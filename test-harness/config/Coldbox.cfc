/**
 * Configures a host application with a custom exceptionHandler.
 * ColdBox does not log unhandled exceptions in this setup, so tests use the
 * module's onException interceptor.
 */
component {

	/**
	 * configure
	 *
	 * Configures the test harness.
	 */
	function configure(){
		/* ERRORALERTS_MAILER=smtp sends mail to a local SMTP server. Tests need
		 * the default in-memory mailer so they can inspect sent messages. */
		var mailer    = getSystemSetting( "ERRORALERTS_MAILER", "default" );
		var smtpMode  = mailer == "smtp";

		// Configure ColdBox request and exception handling.
		variables.coldbox = {
			// Name the test application.
			appName                 : "errorAlerts Harness",
			// Reload handlers during development.
			reinitPassword          : "",
			handlersIndexAutoReload : true,
			modulesExternalLocation : [],
			// Set the default handler action.
			defaultEvent            : "Main.index",
			// Use a custom exception handler to test the interceptor path.
			exceptionHandler        : "main.onException",
			// Show the full error in the browser. This is a local test harness.
			customErrorTemplate     : "/coldbox/system/exceptions/Whoops.cfm",
			// Disable caches so tests use current handlers and events.
			handlerCaching          : false,
			eventCaching            : false
		};

		// Treat loopback requests as the development environment.
		variables.environments = { development : "localhost,127\.0\.0\.1" };

		// Start with the console appender. The module adds its appender on load.
		variables.logBox = {
			appenders : { console : { class : "ConsoleAppender" } },
			root      : { levelmax : "INFO", appenders : "*" },
			info      : [ "coldbox.system" ]
		};

		// Throw from a harness interceptor when rc.harnessFail is set.
		variables.interceptors = [ { class : "root.interceptors.HarnessFailure", name : "HarnessFailure" } ];

		// Configure dependencies and the module under test.
		variables.moduleSettings = {
			cbmailservices : {
				defaultProtocol : mailer,
				mailers         : {
					// Keep sent mail in memory so tests can inspect it.
					"default" : { class : "InMemory" },
					// Send through the cfmail tag to a real SMTP server.
					"smtp"    : { class : "CFMail" }
				},
				/* CFMailProtocol passes these defaults to cfmail. Disable spooling so
				 * Adobe reports delivery errors during the request. */
				defaults        : {
					server      : getSystemSetting( "ERRORALERTS_SMTP_SERVER", "127.0.0.1" ),
					port        : getSystemSetting( "ERRORALERTS_SMTP_PORT", 25 ),
					spoolEnable : false
				},
				runQueueTask    : false
			},
			errorAlerts : {
				to            : getSystemSetting( "ERRORALERTS_TO", "alerts@example.com" ),
				from          : getSystemSetting( "ERRORALERTS_FROM", "harness@example.com" ),
				subjectPrefix : "[Harness]",
				// Send immediately so tests can inspect mail without waiting.
				deliveryMode  : "send",
				/* Keep this override partial to test that module startup restores rc,
				 * cgi, and extraInfo defaults. session keeps its normal false value. */
				includeScopes : { session : false },
				/* The module ships with an empty maskKeys: masking is opt-in.
				 * The harness opts in so the masking demo routes and the
				 * integration specs have field names to hide. */
				maskKeys      : [
					"password",
					"passwd",
					"token",
					"secret",
					"apikey",
					"api_key",
					"authorization",
					"creditcard",
					"creditCardNumber",
					"cvv"
				]
			}
		};

		/* Use a shorter throttle window for SMTP previews. Include every nested key
		 * because ColdBox replaces the whole throttle struct. */
		if ( smtpMode ) {
			variables.moduleSettings.errorAlerts.throttle = {
				maxPerWindow         : 3,
				windowSeconds        : 60,
				maxTrackedSignatures : 500
			};
			variables.moduleSettings.errorAlerts.digestFlushSeconds = 20;
		}
	}

	/**
	 * afterAspectsLoad
	 *
	 * Loads the module from the repository after the application starts.
	 *
	 * @event         The current request context.
	 * @interceptData Data passed to this interception point.
	 * @rc            The request collection.
	 * @prc           The private request collection.
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ){
		controller
			.getModuleService()
			.registerAndActivateModule( moduleName = request.MODULE_NAME, invocationPath = "moduleroot" );
	}

}
