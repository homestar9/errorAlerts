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
			/* How many distinct routes and client IPs a digest email lists from
			 * the occurrences seen during one throttle window. Values past the
			 * cap are counted but not listed. 0 turns sampling off. */
			digestSampleSize     : 5,
			// Ignore category prefixes that would create duplicate or recursive
			// alerts. Removing cbmailservices can alert on a failed alert email.
			// Removing coldbox.system.Bootstrap can report one exception twice.
			ignoreCategories     : [ "cbmailservices", "coldbox.system.Bootstrap" ],
			// Ignore exceptions with one of these exact type values.
			ignoreExceptionTypes : [],
			/* ColdBox's RestHandler.onAnyOtherException() logs an exception and
			 * then announces onException on the next line, so a REST app gets
			 * two emails for one error. This drops the logged copy and keeps
			 * the announced one, which is the only copy carrying a real
			 * tagContext and so the only one that can show a stack trace and a
			 * code snippet. ignoreCategories cannot do this, because
			 * RestHandler logs under the calling handler's own category, which
			 * differs for every handler. Set false only if you have
			 * unregistered UnhandledExceptionCapture@errorAlerts. */
			suppressDuplicateFrameworkLogs : true,
			// Replace numbers and UUIDs before creating a signature.
			normalizeSignatures  : true,
			// Limit the content included in each email.
			maxBodyBytes         : 102400,
			rcValueMaxLength     : 200,
			stackFrames          : 10,
			/* Path prefixes that mark a stack frame as application code, matched
			 * against the path relative to the application root. When every shown
			 * frame is framework code, the first frame matching one of these
			 * prefixes is added to the email as the "application caller" so the
			 * developer can see which line of their own code triggered the error.
			 * /modules/ is deliberately absent: that is where dependencies live. */
			applicationFramePrefixes : [
				"/handlers/",
				"/models/",
				"/views/",
				"/layouts/",
				"/config/",
				"/interceptors/",
				"/modules_app/"
			],
			/* session adds the session id so repeat alerts from one visitor can be
			 * tied together. Off by default: a live session id in an email is
			 * enough to impersonate that visitor. */
			includeScopes        : { rc : true, cgi : true, extraInfo : true, session : false },
			/* Lines of source either side of the failing line, shown in the email
			 * the way ColdBox's Whoops page shows them. 0 turns it off. Costs one
			 * file read per alert and puts application source in the email. */
			codeSnippetLines     : 5,
			/* Describes the logged-in user for the "user" row. Set a closure that
			 * receives WireBox and returns a display string, or "" for nobody.
			 * A closure keeps the module independent of any auth library:
			 *   userProvider : function( wirebox ){
			 *       var auth = wirebox.getInstance( "authenticationService@cbauth" );
			 *       return auth.isLoggedIn() ? auth.getUser().getEmail() : "";
			 *   }
			 * Errors thrown by the closure are swallowed, never sent. */
			userProvider         : "",
			// Shorten file paths in the origin and stack frames by removing the
			// application root, so a path reads "/handlers/Main.cfc". Set false to
			// keep the full absolute path. Paths outside the application root are
			// always shown in full either way.
			relativePaths        : true,
			/* Include the bound parameter values from a failed query. Best field
			 * for reproducing a database error, but it prints whatever a visitor
			 * typed, and maskKeys cannot filter it because the values carry no
			 * field names. Set false to leave them out. */
			includeQueryParams   : true,
			// Also apply maskKeys to the query string shown in the Request
			// section. Set false to print the query string exactly as sent.
			// Turning this off can put a secret from a GET request in email.
			maskQueryString      : true,
			// Text shown in the Request section for a value the request did not
			// provide. `route` and `path` are only set on routed URLs, `referer`
			// only when the browser sent one, and forwardedFor only behind a proxy.
			emptyValueText       : "N/A",
			/* Request headers named here are shown in the Request section, matched
			 * ignoring case. Cookie and Authorization are never included, even
			 * when listed here: both carry credentials. */
			includeHeaders       : [ "Content-Type" ],
			/* Include the raw request body in the email. Off by default. A JSON or
			 * API request puts its payload in the body, not in rc, so a failing
			 * API call is otherwise invisible. JSON bodies get their top-level
			 * fields masked with maskKeys. Form posts are skipped because the rc
			 * table already shows those fields, masked. */
			includeRequestBody   : false,
			// Cap the request body at this many characters.
			requestBodyMaxLength : 4000,
			/* Mask the value of any rc key or query string field named here.
			 * The match is exact apart from case, so every field an application
			 * wants hidden must be listed by its real name. `password` does not
			 * cover `newPassword`. These defaults are only the common names —
			 * check the actual form field names in your own app and add them. */
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
