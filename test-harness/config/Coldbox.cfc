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
		/* Set ERRORALERTS_MAILER=smtp in .env to send real email to a local SMTP
		 * server instead of the in-memory mailbox. The TestBox specs read the
		 * in-memory mailbox, so "default" has to stay the fallback. */
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
				/* MailService.newMail() copies these into every mail payload and
				 * CFMailProtocol hands the payload straight to cfmail. spoolEnable
				 * has to be false or Adobe writes the mail to disk and sends it on a
				 * timer, which hides delivery errors. */
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

		/* Shorten the throttle window during SMTP preview so a digest email arrives
		 * about a minute after a burst instead of ten. ColdBox merges module
		 * settings one level deep, so every throttle key has to be listed here.
		 * maxPerWindow stays at 3 because EndToEndAlertTest asserts 3-of-5. */
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
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ){
		controller
			.getModuleService()
			.registerAndActivateModule( moduleName = request.MODULE_NAME, invocationPath = "moduleroot" );
	}

}
