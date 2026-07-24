/**
 * ErrorAlertAppender
 *
 * Receives root logger events that match the registered severity range and
 * passes them to CaptureService.
 *
 * LogBox creates appenders directly instead of using WireBox, so injected
 * properties are unavailable. This component resolves CaptureService through
 * the injector provided by LogBox.
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
	 * The request flag must be checked before capture. Moving it later would
	 * allow an error during capture to enter this appender again.
	 * Events from this module are skipped so its own errors do not create alerts.
	 * Internal failures go to System.err because LogBox would call this appender
	 * again for another matching error.
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
