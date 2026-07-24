/**
 * PayloadBuilder
 *
 * Turns a LogBox LogEvent (plus live request state) into a notifier-agnostic
 * payload struct. Notifiers only ever see these structs, never LogBox or
 * ColdBox objects -- that is what keeps the notifier seam clean.
 *
 * Every section is built inside its own try/catch: an error logged from a
 * scheduled task or thread has no request context, and that must produce an
 * empty section, never a throw.
 */
component singleton accessors="true" {

	// Injected properties
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";
	property name="coldbox"  inject="coldbox";

	/**
	 * Constructor. Keeps a LogLevels instance handy for number-to-name lookups.
	 */
	function init(){
		variables.logLevels = new coldbox.system.logging.LogLevels();
		return this;
	}

	/**
	 * Builds the "error" payload for one alert email.
	 *
	 * @logEvent   The LogBox LogEvent being alerted on.
	 * @signature  The error signature, shown in the email footer.
	 * @occurrence Which occurrence within the throttle window this is.
	 */
	struct function build(
		required any logEvent,
		required string signature,
		required numeric occurrence
	){
		var payload = {
			type          : "error",
			severity      : levelName( arguments.logEvent.getSeverity() ),
			category      : arguments.logEvent.getCategory(),
			message       : arguments.logEvent.getMessage(),
			timestamp     : arguments.logEvent.getTimestamp(),
			appName       : safeSetting( "appName" ),
			environment   : safeSetting( "environment" ),
			moduleVersion : moduleVersion(),
			signature     : arguments.signature,
			occurrence    : arguments.occurrence,
			maxPerWindow  : settings.throttle.maxPerWindow,
			windowSeconds : settings.throttle.windowSeconds,
			exception     : buildException( arguments.logEvent.getExtraInfo() ),
			request       : buildRequest(),
			rc            : {},
			extraInfo     : ""
		};

		if ( settings.includeScopes.rc ) {
			payload.rc = buildRc();
		}

		// extraInfo only renders separately when it was NOT the exception itself.
		if ( settings.includeScopes.extraInfo && payload.exception.isEmpty() ) {
			payload.extraInfo = stringify( arguments.logEvent.getExtraInfo(), 2000 );
		}

		return payload;
	}

	/**
	 * Builds the "digest" payload from a retired throttle window seed.
	 *
	 * @seed The digest seed from ThrottleService.
	 */
	struct function buildDigest( required struct seed ){
		return {
			type            : "digest",
			severity        : levelName( arguments.seed.severity ),
			signature       : arguments.seed.signature,
			category        : arguments.seed.category,
			message         : arguments.seed.message,
			totalCount      : arguments.seed.totalCount,
			sentCount       : arguments.seed.sentCount,
			suppressedCount : arguments.seed.suppressedCount,
			firstSeen       : arguments.seed.firstSeen,
			lastSeen        : arguments.seed.lastSeen,
			windowSeconds   : arguments.seed.windowSeconds,
			appName         : safeSetting( "appName" ),
			environment     : safeSetting( "environment" ),
			moduleVersion   : moduleVersion()
		};
	}

	/**
	 * Maps a numeric LogBox severity to its name ("ERROR"), falling back to the
	 * raw value for anything LogLevels does not recognize.
	 *
	 * @severity The numeric severity from the log event.
	 */
	private string function levelName( required any severity ){
		var name = variables.logLevels.lookup( arguments.severity );
		return isNull( name ) ? toString( arguments.severity ) : name;
	}

	/**
	 * Reads a ColdBox setting, returning "" instead of throwing when the
	 * setting is missing or the controller is unavailable.
	 *
	 * @name The setting name.
	 */
	private string function safeSetting( required string name ){
		try {
			return coldbox.getSetting( arguments.name );
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * Reads this module's version from the ColdBox module registry, for the
	 * email footer. Returns "" when unavailable.
	 */
	private string function moduleVersion(){
		try {
			return coldbox.getSetting( "modules" ).errorAlerts.version;
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * Extracts a compact exception block when extraInfo is an exception:
	 * type, message, detail, and the top settings.stackFrames tagContext frames
	 * reduced to template + line. Returns {} for non-exception extraInfo.
	 *
	 * @extraInfo The log event's extraInfo value, any type.
	 */
	private struct function buildException( required any extraInfo ){
		try {
			// cfcatch objects are struct-like but not true structs on Adobe CF,
			// so detection mirrors LogEvent.getExtraInfoAsString().
			if (
				!( isObject( arguments.extraInfo ) || isStruct( arguments.extraInfo ) )
				|| !structKeyExists( arguments.extraInfo, "message" )
				|| !structKeyExists( arguments.extraInfo, "stacktrace" )
			) {
				return {};
			}

			var exception = {
				type       : structKeyExists( arguments.extraInfo, "type" ) ? toString( arguments.extraInfo.type ) : "",
				message    : structKeyExists( arguments.extraInfo, "message" ) ? toString( arguments.extraInfo.message ) : "",
				detail     : structKeyExists( arguments.extraInfo, "detail" ) ? toString( arguments.extraInfo.detail ) : "",
				tagContext : []
			};

			if (
				structKeyExists( arguments.extraInfo, "tagContext" )
				&& isArray( arguments.extraInfo.tagContext )
			) {
				var frames = arguments.extraInfo.tagContext;
				var max    = min( frames.len(), settings.stackFrames );
				for ( var i = 1; i <= max; i++ ) {
					exception.tagContext.append( {
						template : structKeyExists( frames[ i ], "template" ) ? frames[ i ].template : "",
						line     : structKeyExists( frames[ i ], "line" ) ? frames[ i ].line : 0
					} );
				}
			}

			return exception;
		} catch ( any e ) {
			return {};
		}
	}

	/**
	 * Snapshots the current request: the ColdBox event/route plus a fixed CGI
	 * subset (never the whole scope). Returns an empty struct when there is no
	 * usable request context, e.g. errors logged from scheduled tasks.
	 */
	private struct function buildRequest(){
		var info = structNew( "ordered" );

		try {
			var event         = coldbox.getRequestService().getContext();
			info[ "event" ]   = event.getCurrentEvent();
			info[ "route" ]   = event.getCurrentRoutedUrl();
		} catch ( any e ) {
		}

		if ( settings.includeScopes.cgi ) {
			try {
				info[ "method" ]      = cgi.request_method;
				info[ "host" ]        = cgi.http_host;
				info[ "path" ]        = cgi.path_info;
				info[ "queryString" ] = cgi.query_string;
				info[ "referer" ]     = cgi.http_referer;
				info[ "remoteAddr" ]  = cgi.remote_addr;
				info[ "userAgent" ]   = cgi.http_user_agent;
				info[ "serverName" ]  = cgi.server_name;
			} catch ( any e ) {
			}
		}

		return info;
	}

	/**
	 * Snapshots the request collection through sanitizeScope(). Returns an
	 * empty struct when there is no request context.
	 */
	private struct function buildRc(){
		try {
			return sanitizeScope( coldbox.getRequestService().getContext().getCollection() );
		} catch ( any e ) {
			return {};
		}
	}

	/**
	 * Sanitizes a scope for email: every value becomes a bounded string.
	 * Keys matching settings.maskKeys (substring match) are masked, binaries
	 * become size labels, objects become class labels, and arrays/structs are
	 * serialized then truncated. This is the writeDump() replacement.
	 *
	 * @scope The struct to sanitize (e.g. rc).
	 */
	private struct function sanitizeScope( required struct scope ){
		var clean = structNew( "ordered" );
		for ( var key in arguments.scope ) {
			clean[ key ] = sanitizeValue( key, arguments.scope[ key ] );
		}
		return clean;
	}

	/**
	 * Sanitizes one value by key: mask first, then bound by type.
	 *
	 * @key   The scope key, checked against settings.maskKeys.
	 * @value The value to sanitize, any type.
	 */
	private string function sanitizeValue( required string key, required any value ){
		for ( var masked in settings.maskKeys ) {
			if ( arguments.key.findNoCase( masked ) ) {
				return "*** masked ***";
			}
		}

		if ( isBinary( arguments.value ) ) {
			return "[binary, #len( arguments.value )# bytes]";
		}

		if ( isSimpleValue( arguments.value ) ) {
			return truncate( toString( arguments.value ), settings.rcValueMaxLength );
		}

		if ( isObject( arguments.value ) ) {
			try {
				return "[object #getMetadata( arguments.value ).name#]";
			} catch ( any e ) {
				return "[object]";
			}
		}

		return truncate( stringify( arguments.value, settings.rcValueMaxLength ), settings.rcValueMaxLength );
	}

	/**
	 * Serializes a complex value to JSON, bounded, without ever throwing.
	 *
	 * @value     The value to serialize, any type.
	 * @maxLength The maximum length of the returned string.
	 */
	private string function stringify( required any value, required numeric maxLength ){
		try {
			if ( isSimpleValue( arguments.value ) ) {
				return truncate( toString( arguments.value ), arguments.maxLength );
			}
			return truncate( serializeJSON( arguments.value ), arguments.maxLength );
		} catch ( any e ) {
			return "[unserializable value]";
		}
	}

	/**
	 * Clips a string to a maximum length, appending an ellipsis when clipped.
	 *
	 * @text      The string to clip.
	 * @maxLength The maximum length before clipping.
	 */
	private string function truncate( required string text, required numeric maxLength ){
		if ( arguments.text.len() <= arguments.maxLength ) {
			return arguments.text;
		}
		return arguments.text.left( arguments.maxLength ) & "…";
	}

}
