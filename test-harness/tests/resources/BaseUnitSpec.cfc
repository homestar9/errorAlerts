/**
 * Loads the shared ColdBox services and fixtures used by unit specs.
 * Individual specs still create and mock the objects they test.
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	// Load ColdBox once and share it across test bundles.
	this.loadColdBox   = true;
	this.unloadColdBox = false;

	/**
	 * beforeAll
	 *
	 * Connects this spec to WireBox before its tests run.
	 */
	function beforeAll(){
		super.beforeAll();
		application.wirebox.autowire( this );
	}

	/**
	 * defaultSettings
	 *
	 * Returns the default module settings used by unit tests.
	 */
	struct function defaultSettings(){
		return {
			enabled              : true,
			to                   : "alerts@example.com",
			from                 : "harness@example.com",
			subjectPrefix        : "[Harness]",
			notifier             : "EmailNotifier@errorAlerts",
			deliveryMode         : "send",
			levelMin             : "FATAL",
			levelMax             : "ERROR",
			throttle             : { maxPerWindow : 3, windowSeconds : 600, maxTrackedSignatures : 500 },
			digestFlushSeconds   : 60,
			ignoreCategories     : [ "cbmailservices", "coldbox.system.Bootstrap" ],
			ignoreExceptionTypes : [],
			normalizeSignatures  : true,
			maxBodyBytes         : 102400,
			rcValueMaxLength     : 200,
			stackFrames          : 10,
			includeScopes        : { rc : true, cgi : true, extraInfo : true },
			maskKeys             : [
				"password",
				"passwd",
				"token",
				"secret",
				"apikey",
				"api_key",
				"authorization",
				"creditcard",
				"cvv"
			]
		};
	}

	/**
	 * newLogEvent
	 *
	 * Builds a LogBox event for a test.
	 *
	 * @message   The log message.
	 * @severity  The numeric severity (1 = ERROR).
	 * @extraInfo Extra info; pass an exception-shaped struct to simulate a crash.
	 * @category  The logging category.
	 */
	any function newLogEvent(
		string message = "Something failed",
		numeric severity = 1,
		any extraInfo = "",
		string category = "tests.fixture"
	){
		return new coldbox.system.logging.LogEvent( argumentCollection = arguments );
	}

	/**
	 * newExceptionInfo
	 *
	 * Builds exception data for a test.
	 *
	 * @template The template of the top stack frame.
	 * @line     The line of the top stack frame.
	 */
	struct function newExceptionInfo( string template = "/app/models/OrderService.cfc", numeric line = 42 ){
		return {
			type       : "HarnessBoom",
			message    : "Fixture explosion",
			detail     : "Deliberate test exception",
			stacktrace : "java.lang.Exception: Fixture explosion",
			tagContext : [
				{ template : arguments.template, line : arguments.line },
				{ template : "/app/handlers/Orders.cfc", line : 10 },
				{ template : "/coldbox/system/EventHandler.cfc", line : 99 }
			]
		};
	}

}
