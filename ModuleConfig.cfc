/**
 * errorAlerts Module Configuration
 *
 * Registers the LogBox appender and unhandled-exception interceptor. Captured
 * events pass through throttling before the configured notifier receives them.
 */
component {

	// ColdBox reads these module properties during startup.
	this.title              = "errorAlerts";
	this.author             = "Angry Sam Productions, Inc.";
	this.webURL             = "https://github.com/homestar9/errorAlerts";
	this.description        = "Throttled error notifications (first-N + digest) for ColdBox apps.";
	// Read the version from box.json so it is defined in one place.
	this.version            = readPackageVersion();
	this.viewParentLookup   = false;
	this.layoutParentLookup = false;
	// This module has no handlers, views, or routes.
	this.entryPoint         = "";
	this.inheritEntryPoint  = false;
	this.modelNamespace     = "errorAlerts";
	this.cfmapping          = "errorAlerts";
	this.autoMapModels      = true;
	this.dependencies       = [ "cbmailservices" ];

	/**
	 * configure
	 *
	 * Defines the default module settings.
	 * Applications can override them in config/modules/errorAlerts.cfc.
	 */
	function configure(){
		variables.settings = {
			// Set false to load the module without registering its services.
			enabled              : true,
			// EmailNotifier requires a recipient. A blank value keeps it inactive.
			to                   : "",
			// A blank sender uses the recipient address.
			from                 : "",
			// A blank prefix uses the ColdBox application name.
			subjectPrefix        : "",
			// Set a WireBox ID that implements INotifier.
			notifier             : "EmailNotifier@errorAlerts",
			// "queue" sends later. "send" waits for email delivery.
			deliveryMode         : "queue",
			// Set the LogBox severity range that produces alerts.
			levelMin             : "FATAL",
			levelMax             : "ERROR",
			// Limit immediate alerts for each signature during a fixed window.
			throttle             : {
				maxPerWindow         : 3,
				windowSeconds        : 600,
				maxTrackedSignatures : 500
			},
			// Check expired throttle windows at this interval.
			digestFlushSeconds   : 60,
			// Ignore category prefixes that would create duplicate or recursive
			// alerts. Removing cbmailservices can alert on a failed alert email.
			// Removing coldbox.system.Bootstrap can report one exception twice.
			ignoreCategories     : [ "cbmailservices", "coldbox.system.Bootstrap" ],
			// Ignore exceptions with one of these exact type values.
			ignoreExceptionTypes : [],
			// Replace numbers and UUIDs before creating a signature.
			normalizeSignatures  : true,
			// Limit the content included in each email.
			maxBodyBytes         : 102400,
			rcValueMaxLength     : 200,
			stackFrames          : 10,
			includeScopes        : { rc : true, cgi : true, extraInfo : true },
			// Mask an rc value when its key contains one of these strings,
			// ignoring case. Removing a term can expose matching values in email.
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
	 * onLoad
	 *
	 * Registers the appender and interceptor when the module is active.
	 * LogBox ignores a second appender registration with the same name.
	 */
	function onLoad(){
		var moduleSettings = controller.getSetting( "moduleSettings" ).errorAlerts;

		if ( !isActive( moduleSettings ) ) {
			return;
		}

		var logBox = controller.getLogBox();
		logBox.registerAppender(
			name     = "errorAlerts",
			class    = "errorAlerts.models.ErrorAlertAppender",
			levelMin = toLevel( moduleSettings.levelMin ),
			levelMax = toLevel( moduleSettings.levelMax )
		);
		logBox.getRootLogger().addAppender( logBox.getAppenderRegistry()[ "errorAlerts" ] );

		/* A custom ColdBox exceptionHandler prevents Bootstrap from logging the
		 * exception, so the appender cannot capture that exception on its own. */
		controller.getInterceptorService().registerInterceptor(
			interceptorClass = "errorAlerts.interceptors.UnhandledExceptionCapture",
			interceptorName  = "UnhandledExceptionCapture@errorAlerts"
		);
	}

	/**
	 * onUnload
	 *
	 * Removes the appender and interceptor during module shutdown.
	 * Cleanup failures do not stop the shutdown.
	 */
	function onUnload(){
		try {
			controller.getLogBox().getRootLogger().removeAppender( "errorAlerts" );
		} catch ( any e ) {
		}
		try {
			controller.getInterceptorService().unregister( "UnhandledExceptionCapture@errorAlerts" );
		} catch ( any e ) {
		}
	}

	/**
	 * isActive
	 *
	 * Checks whether the settings allow the module to register.
	 * EmailNotifier also requires a recipient address.
	 *
	 * @settings The merged module settings struct.
	 */
	private boolean function isActive( required struct settings ){
		if ( !arguments.settings.enabled ) {
			return false;
		}

		if (
			arguments.settings.notifier == "EmailNotifier@errorAlerts"
			&& !arguments.settings.to.trim().len()
		) {
			createObject( "java", "java.lang.System" ).out.println(
				"errorAlerts: setting `to` is blank, so no alerts will be sent. Set it in config/modules/errorAlerts.cfc."
			);
			return false;
		}

		return true;
	}

	/**
	 * toLevel
	 *
	 * Returns the LogBox number for a level name.
	 * Throws when the name is invalid so startup cannot use the wrong range.
	 *
	 * @name The level name from settings.
	 */
	private numeric function toLevel( required string name ){
		var level = new coldbox.system.logging.LogLevels().lookupAsInt( arguments.name );
		if ( level == 999 ) {
			throw(
				type    = "errorAlerts.InvalidLevel",
				message = "errorAlerts: '#arguments.name#' is not a valid LogBox level. Use OFF, FATAL, ERROR, WARN, INFO or DEBUG."
			);
		}
		return level;
	}

	/**
	 * readPackageVersion
	 *
	 * Reads the module version from box.json.
	 * This must run before configure() because ColdBox reads this.version first.
	 * Returns an empty string when box.json cannot be read.
	 */
	private string function readPackageVersion(){
		try {
			var boxJsonPath = getDirectoryFromPath( getCurrentTemplatePath() ) & "box.json";

			if ( !fileExists( boxJsonPath ) ) {
				return "";
			}

			var boxJson = deserializeJSON( fileRead( boxJsonPath ) );

			return boxJson.keyExists( "version" ) ? boxJson.version : "";
		} catch ( any e ) {
			return "";
		}
	}

}
