/**
 * PayloadBuilder
 *
 * Converts a LogBox event and available request data into a plain struct.
 * Request sections return empty values when no request context exists.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";
	property name="coldbox"  inject="coldbox";

	/**
	 * init
	 *
	 * Creates the LogLevels helper used for severity names.
	 */
	function init(){
		variables.logLevels = new coldbox.system.logging.LogLevels();
		return this;
	}

	/**
	 * build
	 *
	 * Builds the payload for one error alert.
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

		// Add extraInfo only when it was not already added as an exception.
		if ( settings.includeScopes.extraInfo && payload.exception.isEmpty() ) {
			payload.extraInfo = stringify( arguments.logEvent.getExtraInfo(), 2000 );
		}

		return payload;
	}

	/**
	 * buildDigest
	 *
	 * Builds a digest payload from an expired throttle window.
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
	 * levelName
	 *
	 * Returns the LogBox name for a severity.
	 * Returns the original value when LogBox does not recognize it.
	 *
	 * @severity The numeric severity from the log event.
	 */
	private string function levelName( required any severity ){
		var name = variables.logLevels.lookup( arguments.severity );
		return isNull( name ) ? toString( arguments.severity ) : name;
	}

	/**
	 * safeSetting
	 *
	 * Reads a ColdBox setting or returns an empty string.
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
	 * moduleVersion
	 *
	 * Reads the module version for the email footer.
	 * Returns an empty string when the registry is unavailable.
	 */
	private string function moduleVersion(){
		try {
			return coldbox.getSetting( "modules" ).errorAlerts.version;
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * buildException
	 *
	 * Returns basic exception fields and a limited list of stack frames.
	 * Returns an empty struct when extraInfo is not an exception.
	 *
	 * @extraInfo The log event's extraInfo value, any type.
	 */
	private struct function buildException( required any extraInfo ){
		try {
			// Adobe ColdFusion cfcatch values can be objects instead of structs.
			// Accept either form before checking the required exception keys.
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
	 * buildRequest
	 *
	 * Returns the ColdBox event, route, and selected CGI values.
	 * Missing request data is omitted.
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
	 * buildRc
	 *
	 * Returns a sanitized request collection.
	 * Returns an empty struct when no request context exists.
	 */
	private struct function buildRc(){
		try {
			return sanitizeScope( coldbox.getRequestService().getContext().getCollection() );
		} catch ( any e ) {
			return {};
		}
	}

	/**
	 * sanitizeScope
	 *
	 * Converts each scope value to a limited string for email.
	 * Sensitive keys are masked before their values are converted.
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
	 * sanitizeValue
	 *
	 * Masks a sensitive key or converts its value to a limited string.
	 * The key check is a case-insensitive substring match. It must happen first
	 * so request secrets are not serialized into alert email.
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
	 * stringify
	 *
	 * Converts a value to a limited string without throwing.
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
	 * truncate
	 *
	 * Limits a string to the given character count and adds an ellipsis.
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
