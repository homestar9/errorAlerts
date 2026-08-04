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
			digestSampleSize     : 5,
			ignoreCategories     : [ "cbmailservices", "coldbox.system.Bootstrap" ],
			ignoreExceptionTypes : [],
			normalizeSignatures  : true,
			maxBodyBytes         : 102400,
			rcValueMaxLength     : 200,
			stackFrames          : 10,
			applicationFramePrefixes : [
				"/handlers/",
				"/models/",
				"/views/",
				"/layouts/",
				"/config/",
				"/interceptors/",
				"/modules_app/"
			],
			includeScopes        : { rc : true, cgi : true, extraInfo : true, session : false },
			codeSnippetLines     : 5,
			userProvider         : "",
			relativePaths        : true,
			includeQueryParams   : true,
			maskQueryString      : true,
			emptyValueText       : "N/A",
			includeHeaders       : [ "Content-Type" ],
			includeRequestBody   : false,
			requestBodyMaxLength : 4000,
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

	/**
	 * newDeepExceptionInfo
	 *
	 * Builds exception data with a deep stack: the first eleven frames are
	 * framework and dependency code (including one driver frame), the first
	 * application-owned frame sits at position 13, past the default ten-frame
	 * display cap. Mirrors a real ORM failure, where the application's own
	 * view or handler is buried under module frames.
	 *
	 * @callerTemplate The application frame's template path.
	 * @callerLine     The application frame's line.
	 */
	struct function newDeepExceptionInfo(
		string callerTemplate = "/app/views/posts/_card.cfm",
		numeric callerLine = 14
	){
		var frames = [
			{ template : "/app/modules/qb/models/Grammars/BaseGrammar.cfc", line : 128 },
			{ template : "|SQLServer|6.0.0.1282|", line : 1085 }
		];
		for ( var i = 3; i <= 11; i++ ) {
			frames.append( { template : "/app/modules/quick/models/BaseEntity.cfc", line : 2500 + i } );
		}
		frames.append( { template : "/coldbox/system/web/Renderer.cfc", line : 400 } );
		frames.append( { template : arguments.callerTemplate, line : arguments.callerLine } );
		frames.append( { template : "/coldbox/system/web/Renderer.cfc", line : 550 } );
		frames.append( { template : "/coldbox/system/EventHandler.cfc", line : 99 } );
		frames.append( { template : "/coldbox/system/Bootstrap.cfc", line : 275 } );

		return {
			type       : "Database",
			message    : "Fixture SQL failure",
			detail     : "Deliberate deep-stack test exception",
			stacktrace : "java.sql.SQLException: Fixture SQL failure",
			tagContext : frames
		};
	}

}
