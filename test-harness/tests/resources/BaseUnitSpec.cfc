/**
 * Base for unit specs. Loads the virtual ColdBox app once (so the /errorAlerts
 * mapping, WireBox, and module settings exist) and keeps it alive between
 * bundles -- restarting per file multiplies suite time with no isolation gain.
 * Specs build their objects with `new` + $property() mocks, so they stay unit
 * tests despite the loaded app.
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	// Load on first test, keep alive between bundles.
	this.loadColdBox   = true;
	this.unloadColdBox = false;

	/**
	 * Wires the spec itself so getInstance() and injections work.
	 */
	function beforeAll(){
		super.beforeAll();
		application.wirebox.autowire( this );
	}

	/**
	 * The default module settings struct used by unit specs, mirroring
	 * ModuleConfig.configure(). Override individual keys per spec.
	 */
	struct function defaultSettings(){
		return {
			enabled              : true,
			environments         : [ "development" ],
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
	 * Builds a LogBox LogEvent fixture.
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
	 * Builds a cfcatch-shaped struct fixture for exception scenarios.
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
