/**
 * Harness ColdBox configuration. Deliberately mirrors a HOST app that defines
 * its own `exceptionHandler`: with one configured, ColdBox never logs unhandled
 * exceptions through LogBox, so the suite exercises the module's onException
 * interceptor path -- the path real hosts like northbaywaterheaters-web use.
 */
component {

	/**
	 * Configures the harness application.
	 */
	function configure(){
		// coldbox directives
		variables.coldbox = {
			// Application Setup
			appName                 : "errorAlerts Harness",
			// Development Settings
			reinitPassword          : "",
			handlersIndexAutoReload : true,
			modulesExternalLocation : [],
			// Implicit Events
			defaultEvent            : "Main.index",
			// Error/Exception Handling: a custom handler, like a real host.
			exceptionHandler        : "main.onException",
			customErrorTemplate     : "",
			// Application Aspects
			handlerCaching          : false,
			eventCaching            : false
		};

		// The harness always runs on the loopback, so this always matches.
		variables.environments = { development : "localhost,127\.0\.0\.1" };

		// LogBox: console only. The module adds its own appender at onLoad.
		variables.logBox = {
			appenders : { console : { class : "ConsoleAppender" } },
			root      : { levelmax : "INFO", appenders : "*" },
			info      : [ "coldbox.system" ]
		};

		// Module Settings
		variables.moduleSettings = {
			// The InMemory mailer lets specs assert on sent mail synchronously.
			cbmailservices : {
				defaultProtocol : "default",
				mailers         : { "default" : { class : "InMemory" } },
				runQueueTask    : false
			},
			errorAlerts : {
				to            : "alerts@example.com",
				from          : "harness@example.com",
				subjectPrefix : "[Harness]",
				// The harness runs in "development", which the module skips by
				// default -- allow it explicitly, which also exercises the
				// environments allow-list.
				environments  : [ "development" ],
				// Synchronous delivery so specs can assert the mailbox immediately.
				deliveryMode  : "send"
			}
		};
	}

	/**
	 * Loads the module under test from the repo root after the app starts.
	 */
	function afterAspectsLoad( event, interceptData, rc, prc ){
		controller
			.getModuleService()
			.registerAndActivateModule( moduleName = request.MODULE_NAME, invocationPath = "moduleroot" );
	}

}
