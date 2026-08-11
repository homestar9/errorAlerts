/**
 * errorAlerts Module Configuration
 *
 * Registers the LogBox appender and the interceptor that catches unhandled
 * exceptions. The module throttles each event before it sends a notification.
 */
component {

	// ColdBox reads these properties when the module starts.
	this.title              = "errorAlerts";
	this.author             = "Angry Sam Productions, Inc.";
	this.webURL             = "https://github.com/homestar9/errorAlerts";
	this.description        = "Throttled error notifications (first-N + digest) for ColdBox apps.";
	// Keep the version in box.json instead of copying it here.
	this.version            = readPackageVersion();
	this.viewParentLookup   = false;
	this.layoutParentLookup = false;
	// The module does not provide handlers, views, or routes.
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
		var nested = nestedDefaults();

		variables.settings = {
			// Set this to false to load the module without sending alerts.
			enabled              : true,
			// EmailNotifier stays inactive until this address is set.
			to                   : "",
			// A blank sender uses the recipient address.
			from                 : "",
			// A blank prefix uses the ColdBox application name.
			subjectPrefix        : "",
			// WireBox uses this ID to find an INotifier implementation.
			notifier             : "EmailNotifier@errorAlerts",
			// "queue" sends later. "send" waits for email delivery.
			deliveryMode         : "queue",
			// Set the LogBox severity range that produces alerts.
			levelMin             : "FATAL",
			levelMax             : "ERROR",
			// Limit immediate alerts for one error during a fixed window.
			// nestedDefaults() lets a partial application override keep missing defaults.
			throttle             : nested.throttle,
			// Check expired throttle windows at this interval.
			digestFlushSeconds   : 60,
			/* Limit the distinct routes and client IP addresses listed in a digest.
			 * Extra values are counted but not listed. maskKeys cannot hide these IP
			 * addresses because they have no field names. Set this to 0 to omit both
			 * the route and IP address lists. */
			digestSampleSize     : 5,
			// Ignore category prefixes that would create duplicate or recursive
			// alerts. Removing cbmailservices can alert on a failed alert email.
			// Removing coldbox.system.Bootstrap can report one exception twice.
			ignoreCategories     : [ "cbmailservices", "coldbox.system.Bootstrap" ],
			// Ignore exceptions with one of these exact type values.
			ignoreExceptionTypes : [],
			/* RestHandler reports some exceptions twice. It logs the exception and
			 * then announces onException. Keep only the announcement because it has
			 * the tagContext needed for stack frames and source code. Category rules
			 * cannot find every logged copy because each handler uses a different
			 * category. Set this to false only after unregistering
			 * UnhandledExceptionCapture@errorAlerts. */
			suppressDuplicateFrameworkLogs : true,
			// Replace numbers and UUIDs before creating a signature.
			normalizeSignatures  : true,
			// Limit the content included in each email.
			maxBodyBytes         : 102400,
			rcValueMaxLength     : 200,
			stackFrames          : 10,
			/* These path prefixes mark stack frames that belong to the application.
			 * The module compares each prefix with a path relative to the application
			 * root. The first match becomes the "application caller" in the email.
			 * /modules/ is excluded because that folder contains dependencies. */
			applicationFramePrefixes : [
				"/handlers/",
				"/models/",
				"/views/",
				"/layouts/",
				"/config/",
				"/interceptors/",
				"/modules_app/"
			],
			/* session adds the session ID to each alert. Keep it off unless the risk
			 * is acceptable because a live session ID may let someone impersonate
			 * the visitor. nestedDefaults() repairs partial overrides of this struct. */
			includeScopes        : nested.includeScopes,
			/* Show this many source lines before and after the failing line. This
			 * reads one file per alert and puts application source in the email.
			 * Set this to 0 to turn source snippets off. */
			codeSnippetLines     : 5,
			/* Set a closure that receives WireBox and returns the logged-in user's
			 * display name. Return "" when no user is logged in. A closure keeps the
			 * module independent of any authentication library:
			 *   userProvider : function( wirebox ){
			 *       var auth = wirebox.getInstance( "authenticationService@cbauth" );
			 *       return auth.isLoggedIn() ? auth.getUser().getEmail() : "";
			 *   }
			 * An error from the closure is ignored so it cannot stop an alert. */
			userProvider         : "",
			// Remove the application root from paths in the email. Paths outside the
			// application root always remain absolute.
			relativePaths        : true,
			/* Include bound SQL parameter values. These values can help reproduce a
			 * query error. They may also contain user input that maskKeys cannot hide
			 * because the values have no field names. */
			includeQueryParams   : true,
			// Apply the masking settings to query-string fields. Turning this off may
			// expose a secret from a GET request.
			maskQueryString      : true,
			// Show this text when the request did not provide a value.
			emptyValueText       : "N/A",
			/* Show these request headers, ignoring case. Cookie, Authorization, and
			 * Proxy-Authorization are always blocked because they carry credentials. */
			includeHeaders       : [ "Content-Type" ],
			/* Include request bodies that are not form posts. JSON objects and arrays
			 * are walked so fields can be masked at any depth. JSON that cannot be
			 * walked is reported by size. A non-JSON body is shown as sent because it
			 * has no field names for maskKeys to match. */
			includeRequestBody   : false,
			// Cap the request body at this many characters.
			requestBodyMaxLength : 4000,
			/* Mask matching field values in rc, JSON bodies, extraInfo, and query
			 * strings. Matching is exact and ignores case. For example, `password`
			 * does not match `newPassword`. Masking is off by default because each
			 * application uses different field names. The README has a starter list. */
			maskKeys             : [],
			/* Try these wildcard patterns when maskKeys has no exact match. `*`
			 * matches any number of characters. Matching ignores case and covers the
			 * whole field name. Keep patterns narrow so useful fields stay visible. */
			maskKeyPatterns      : [],
			/* Limit each string inside extraInfo or a JSON body. Longer strings keep
			 * their beginning and show their original size. Set this to 0 to disable
			 * this limit. The limits for complete sections still apply. */
			longValueMaxLength   : 500,
			/* Do not apply longValueMaxLength to these exact key names. Matching
			 * ignores case. The defaults keep useful stack frames from being cut off. */
			longValueExemptKeys  : [ "_stacktrace", "stacktrace" ],
			// Cap the sanitized extraInfo output at this many characters.
			extraInfoMaxLength   : 2000,
			/* Cap the exception detail and extendedInfo fields shown in the
			 * email at this many characters. 0 disables the cap. */
			exceptionFieldMaxLength : 2048
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

		/* Repair partial nested settings before any service reads them. The
		 * scheduler can load CaptureService even when alerts are inactive. */
		applyNestedDefaults( moduleSettings );

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

		/* A custom ColdBox exceptionHandler stops Bootstrap from logging the
		 * exception. This interceptor captures that exception instead. */
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
	 * nestedDefaults
	 *
	 * Returns fresh defaults for settings that contain nested structs.
	 * configure() uses the values as defaults. onLoad() uses the same values to
	 * repair partial application overrides.
	 */
	private struct function nestedDefaults(){
		return {
			throttle      : {
				maxPerWindow         : 3,
				windowSeconds        : 600,
				maxTrackedSignatures : 500
			},
			includeScopes : {
				rc        : true,
				cgi       : true,
				extraInfo : true,
				session   : false
			}
		};
	}

	/**
	 * applyNestedDefaults
	 *
	 * Restores keys that a partial `throttle` or `includeScopes` override removed.
	 *
	 * ColdBox replaces a nested struct instead of merging its keys. Missing keys
	 * can stop alert building or disable throttling. This method updates the same
	 * settings struct that WireBox injects into each service. Existing override
	 * values are not changed.
	 *
	 * @settings The merged module settings struct, modified in place.
	 */
	private void function applyNestedDefaults( required struct settings ){
		var defaults = nestedDefaults();

		for ( var name in defaults ) {
			// Replace a missing or invalid nested struct with all of its defaults.
			if (
				!structKeyExists( arguments.settings, name )
				|| !isStruct( arguments.settings[ name ] )
			) {
				arguments.settings[ name ] = defaults[ name ];
				continue;
			}

			// false adds missing keys without replacing application overrides.
			structAppend( arguments.settings[ name ], defaults[ name ], false );
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
	 * ColdBox reads this.version before configure(), so this method runs early.
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
