/**
 * ErrorAlertAppender
 *
 * Passes matching root logger events to CaptureService.
 *
 * LogBox creates appenders without WireBox property injection. This component
 * uses the injector that LogBox provides to load CaptureService.
 */
component extends="coldbox.system.logging.AbstractAppender" accessors="true" {

	/**
	 * init
	 *
	 * Passes the LogBox registration arguments to AbstractAppender.
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
	 * logMessage
	 *
	 * Sends one log event to CaptureService.
	 * The request flag prevents an error during capture from calling this method
	 * again. Events from this module are skipped for the same reason. Internal
	 * failures go to System.err instead of LogBox.
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
			// AbstractAppender creates variables.system before this method runs.
			variables.system.err.println( "errorAlerts appender failed: #e.message# #e.detail#" );
		} finally {
			request.delete( "_errorAlertsCapturing" );
		}

		return this;
	}

	/**
	 * getCaptureService
	 *
	 * Loads CaptureService once from the available WireBox injector.
	 */
	private any function getCaptureService(){
		if ( !variables.keyExists( "captureService" ) ) {
			variables.captureService = getInjector().getInstance( "CaptureService@errorAlerts" );
		}
		return variables.captureService;
	}

	/**
	 * getInjector
	 *
	 * Returns the injector stored by LogBox.
	 * Falls back to the ColdBox controller when getWireBox() is empty.
	 */
	private any function getInjector(){
		if ( !isSimpleValue( getWireBox() ) ) {
			return getWireBox();
		}
		return getColdBox().getWireBox();
	}

}
