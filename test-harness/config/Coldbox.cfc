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
			customErrorTemplate     : "",
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

		// Configure dependencies and the module under test.
		variables.moduleSettings = {
			// Keep sent mail in memory so tests can inspect it.
			cbmailservices : {
				defaultProtocol : "default",
				mailers         : { "default" : { class : "InMemory" } },
				runQueueTask    : false
			},
			errorAlerts : {
				to            : "alerts@example.com",
				from          : "harness@example.com",
				subjectPrefix : "[Harness]",
				// Send immediately so tests can inspect mail without waiting.
				deliveryMode  : "send"
			}
		};
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
