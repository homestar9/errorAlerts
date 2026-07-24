/**
 * errorAlerts Module Configuration
 *
 * Registers a LogBox appender on the ROOT logger at runtime, so the host app
 * never edits its logBox config. The appender catches manual `logger.error()` /
 * `logger.fatal()` calls. A companion `onException` interceptor catches
 * unhandled exceptions, because ColdBox does NOT log those through LogBox when
 * the host defines its own `exceptionHandler` setting.
 *
 * Captured events are throttled per error signature (first N send immediately,
 * the rest roll into one digest email per window) and delivered through the
 * configured notifier. EmailNotifier ships with the module; `settings.notifier`
 * accepts any WireBox ID implementing INotifier, which is the seam for swapping
 * in Sentry or another destination later.
 */
component {

	// Module Properties
	this.title              = "errorAlerts";
	this.author             = "Angry Sam Productions, Inc.";
	this.webURL             = "https://github.com/homestar9/errorAlerts";
	this.description        = "Throttled error notifications (first-N + digest) for ColdBox apps.";
	// NOT hardcoded: box.json is the single source of truth. See readPackageVersion() below.
	this.version            = readPackageVersion();
	this.viewParentLookup   = false;
	this.layoutParentLookup = false;
	// Headless module: no handlers, views, or routes.
	this.entryPoint         = "";
	this.inheritEntryPoint  = false;
	this.modelNamespace     = "errorAlerts";
	this.cfmapping          = "errorAlerts";
	this.autoMapModels      = true;
	this.dependencies       = [ "cbmailservices" ];

	/**
	 * Declares the default module settings. Hosts override them in
	 * config/modules/errorAlerts.cfc; the returned struct merges over these.
	 */
	function configure(){
		variables.settings = {
			// Master switch. false = the module loads but registers nothing.
			enabled              : true,
			// Explicit allow-list of ColdBox environments the module is active in.
			// EMPTY means every environment EXCEPT "development".
			environments         : [],
			// Where alert emails go. REQUIRED for the shipped EmailNotifier:
			// when blank, the module prints one startup warning and stays inactive.
			to                   : "",
			// Sender address. Falls back to `to` when blank.
			from                 : "",
			// Prepended to every subject. Blank = "[<appName>]" resolved per email.
			subjectPrefix        : "",
			// Any WireBox ID implementing errorAlerts.models.notifiers.INotifier.
			// This is the seam for swapping email out for Sentry or anything else.
			notifier             : "EmailNotifier@errorAlerts",
			// "queue" hands the mail to the cbmailservices queue task, off the
			// failing request. "send" delivers synchronously and blocks the
			// request for one SMTP round-trip.
			deliveryMode         : "queue",
			// Severity range the appender listens to. FATAL..ERROR by default;
			// set levelMax to "WARN" to receive warning emails too.
			levelMin             : "FATAL",
			levelMax             : "ERROR",
			// First N + digest throttling, per error signature. The window is
			// fixed and anchored at the signature's first occurrence.
			throttle             : {
				maxPerWindow         : 3,
				windowSeconds        : 600,
				maxTrackedSignatures : 500
			},
			// How often the scheduled task sweeps expired windows for digests.
			digestFlushSeconds   : 60,
			// Category PREFIXES that never alert.
			// - "cbmailservices": a failed alert email must not alert about itself.
			// - "coldbox.system.Bootstrap": unhandled exceptions arrive via this
			//   module's onException interceptor instead. Without this ignore, a
			//   host with NO custom exceptionHandler would get every crash twice.
			ignoreCategories     : [ "cbmailservices", "coldbox.system.Bootstrap" ],
			// Exception `type` values that never alert.
			ignoreExceptionTypes : [],
			// Collapse digit runs and UUIDs before hashing, so "Order 123 failed"
			// and "Order 456 failed" throttle as one signature.
			normalizeSignatures  : true,
			// Email shaping.
			maxBodyBytes         : 102400,
			rcValueMaxLength     : 200,
			stackFrames          : 10,
			includeScopes        : { rc : true, cgi : true, extraInfo : true },
			// rc keys whose values render as "*** masked ***" (substring match).
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
	 * Registers the appender on the root logger plus the unhandled-exception
	 * interceptor, but only when the module is active (see isActive()).
	 * LogBox's registerAppender() is idempotent, so a fwreinit cannot
	 * double-register the appender.
	 */
	function onLoad(){
		var moduleSettings = controller.getSetting( "moduleSettings" ).errorAlerts;

		if ( !isActive( moduleSettings, controller.getSetting( "environment" ) ) ) {
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

		/* When a host configures its own `exceptionHandler`, ColdBox's Bootstrap
		 * only announces the `onException` interception point and never logs the
		 * exception through LogBox (see Bootstrap.processException). The appender
		 * alone would therefore miss unhandled exceptions, so this interceptor
		 * feeds them into the same capture pipeline. */
		controller.getInterceptorService().registerInterceptor(
			interceptorClass = "errorAlerts.interceptors.UnhandledExceptionCapture",
			interceptorName  = "UnhandledExceptionCapture@errorAlerts"
		);
	}

	/**
	 * Removes the appender and interceptor so a module unload/reinit starts
	 * clean. Failures are swallowed: unload hygiene must never break a shutdown.
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
	 * Decides whether the module should register anything.
	 * Active when: `enabled` is true, the current environment is allowed
	 * (empty allow-list = everything except "development"), and, when the
	 * shipped EmailNotifier is in use, `to` is not blank. A blank `to` prints
	 * ONE startup warning so the misconfiguration is loud but harmless.
	 *
	 * @settings    The merged module settings struct.
	 * @environment The current ColdBox environment name.
	 */
	private boolean function isActive( required struct settings, required string environment ){
		if ( !arguments.settings.enabled ) {
			return false;
		}

		var environmentAllowed = arguments.settings.environments.len()
		 ? arguments.settings.environments.findNoCase( arguments.environment ) > 0
		 : arguments.environment != "development";

		if ( !environmentAllowed ) {
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
	 * Maps a level name ("FATAL", "ERROR", "WARN"...) to its LogBox number.
	 * Throws on an unknown name so a settings typo fails loudly at startup
	 * instead of silently registering the wrong level range.
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
	 * Reads this module's version out of box.json, the single source of truth.
	 * Called from the pseudo-constructor because ColdBox harvests this.version
	 * BEFORE configure() runs. Fails soft: a missing or malformed box.json must
	 * never stop the module from registering.
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
