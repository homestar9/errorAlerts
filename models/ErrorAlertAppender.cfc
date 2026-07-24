/**
 * ErrorAlertAppender
 *
 * The LogBox appender the module registers on the host's root logger. It is
 * deliberately dumb: LogBox already filtered by level (only events inside the
 * registered levelMin..levelMax range reach logMessage), so this component only
 * runs two cheap guards and hands the event to CaptureService.
 *
 * LogBox instantiates appenders itself via `new` -- NOT through WireBox -- so
 * `property inject` does not work here. All testable logic therefore lives in
 * WireBox singletons that this appender resolves lazily through getWireBox().
 */
component extends="coldbox.system.logging.AbstractAppender" accessors="true" {

	/**
	 * Constructor. LogBox calls this with the arguments given to
	 * registerAppender(); everything defers to the abstract base.
	 *
	 * @name       The unique name for this appender.
	 * @properties A map of configuration properties for the appender.
	 * @layout     The layout class for custom message rendering (unused here).
	 * @levelMin   Minimum severity this appender listens to.
	 * @levelMax   Maximum severity this appender listens to.
	 */
	function init(
		required name,
		struct properties = {},
		layout            = "",
		levelMin          = 0,
		levelMax          = 4
	){
		super.init( argumentCollection = arguments );
		return this;
	}

	/**
	 * Receives one qualifying log event and delegates to CaptureService.
	 *
	 * Loop protection, in order:
	 * 1. A request-scope flag bails out when an error thrown while we were
	 *    already capturing tries to re-enter this appender.
	 * 2. Events logged under this module's own categories are skipped.
	 * 3. Any internal failure goes to System.err only. It is NEVER rethrown and
	 *    NEVER logged through LogBox -- either would loop straight back here.
	 *
	 * @logEvent The LogBox LogEvent being logged.
	 */
	function logMessage( required any logEvent ){
		if ( request.keyExists( "_errorAlertsCapturing" ) ) {
			return this;
		}

		if ( arguments.logEvent.getCategory().findNoCase( "errorAlerts" ) == 1 ) {
			return this;
		}

		request._errorAlertsCapturing = true;
		try {
			getCaptureService().capture( arguments.logEvent );
		} catch ( any e ) {
			// variables.system comes from AbstractAppender's pseudo-constructor.
			variables.system.err.println( "errorAlerts appender failed: #e.message# #e.detail#" );
		} finally {
			request.delete( "_errorAlertsCapturing" );
		}

		return this;
	}

	/**
	 * Lazily resolves and caches CaptureService through whichever injector
	 * reference LogBox wired onto this appender at registration time.
	 */
	private any function getCaptureService(){
		if ( !variables.keyExists( "captureService" ) ) {
			variables.captureService = getInjector().getInstance( "CaptureService@errorAlerts" );
		}
		return variables.captureService;
	}

	/**
	 * Returns a usable WireBox injector. In a ColdBox app, LogBox is created
	 * with the CONTROLLER reference but an empty wirebox one, so getWireBox()
	 * returns "" here -- reach through the controller instead.
	 */
	private any function getInjector(){
		if ( !isSimpleValue( getWireBox() ) ) {
			return getWireBox();
		}
		return getColdBox().getWireBox();
	}

}
