/**
 * PayloadBuilder
 *
 * Converts a LogBox event and available request data into a plain struct.
 *
 * A ColdBox request provides its event, routing details, and request collection.
 * A web request outside ColdBox provides a "not a ColdBox request" row instead
 * of routing details. Its request collection combines FORM and URL fields.
 * Events outside web requests have no FORM or URL fields to include.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings"        inject="coldbox:moduleSettings:errorAlerts";
	property name="coldbox"         inject="coldbox";
	property name="frameClassifier" inject="FrameClassifier@errorAlerts";

	/**
	 * init
	 *
	 * Creates the LogLevels helper and records the module's paths.
	 * callerFrame() uses the paths to skip this module's stack frames. The paths
	 * are calculated because applications can install the module anywhere.
	 */
	function init(){
		variables.logLevels = new coldbox.system.logging.LogLevels();

		// Limit the search for an application frame on very large call stacks.
		variables.MAX_SCAN_FRAMES = 100;

		// The replacement text for a masked value.
		variables.MASK_TOKEN = "*** masked ***";

		// Limit nested output and stop recursion through self-referencing data.
		variables.MAX_DEPTH = 5;

		/* Charge each visited node for the JSON punctuation it will add. This also
		 * limits work on structs and arrays with many small values. */
		variables.NODE_OVERHEAD = 8;

		// Stop a payload with many unique keys from growing the mask cache forever.
		variables.VERDICT_CACHE_MAX = 1000;

		/* Do not parse a JSON body larger than 2 MB. deserializeJSON() builds the
		 * full value before the limited sanitizer can run. A larger body could use
		 * too much memory while the server is already handling an error. */
		variables.MAX_PARSE_CHARS = 2097152;

		// The directory holding this file, e.g. ".../errorAlerts/models/".
		var modelsPath           = getDirectoryFromPath( getCurrentTemplatePath() ).replace( "\", "/", "all" );
		variables.ownModelsPath  = modelsPath;
		variables.ownInterceptorsPath = modelsPath.reReplaceNoCase( "models/$", "interceptors/" );

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
		// Compile masking once instead of once for every request field.
		ensureMaskConfig();

		var exception = buildException( arguments.logEvent.getExtraInfo() );

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
			exception     : exception,
			request       : buildRequest( exception ),
			runtime       : runtimeInfo(),
			rc            : {},
			requestBody   : "",
			extraInfo     : ""
		};

		if ( settings.includeScopes.rc ) {
			payload.rc = buildRc();
		}

		if ( settings.includeRequestBody ) {
			payload.requestBody = buildRequestBody();
		}

		// Add extraInfo only when it was not already added as an exception.
		if ( settings.includeScopes.extraInfo && payload.exception.isEmpty() ) {
			payload.extraInfo = stringify(
				sanitizeDeep( arguments.logEvent.getExtraInfo() ),
				settingOr( "extraInfoMaxLength", 2000 )
			);
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
		var digest = {
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
			// Each server keeps separate throttle counts and sends its own digest.
			machine         : machineName(),
			moduleVersion   : moduleVersion()
		};

		// Use empty samples when an older digest seed does not include them.
		if ( arguments.seed.keyExists( "samples" ) ) {
			digest.samples = arguments.seed.samples;
		}
		if ( arguments.seed.keyExists( "overflow" ) ) {
			digest.overflow = arguments.seed.overflow;
		}

		return digest;
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
				type            : structKeyExists( arguments.extraInfo, "type" ) ? toString( arguments.extraInfo.type ) : "",
				message         : structKeyExists( arguments.extraInfo, "message" ) ? toString( arguments.extraInfo.message ) : "",
				detail          : structKeyExists( arguments.extraInfo, "detail" ) ? toString( arguments.extraInfo.detail ) : "",
				errorCode       : firstOf( arguments.extraInfo, [ "errorCode", "errNumber" ] ),
				extendedInfo    : firstOf( arguments.extraInfo, [ "extendedInfo" ] ),
				database        : buildDatabaseDetail( arguments.extraInfo ),
				causes          : buildCauses( arguments.extraInfo ),
				snippet         : buildSnippet( arguments.extraInfo ),
				callerSnippet   : { template : "", line : 0, lines : [] },
				tagContext      : [],
				totalFrames     : 0,
				omittedFrames   : 0,
				actionableFrame : {}
			};

			if (
				structKeyExists( arguments.extraInfo, "tagContext" )
				&& isArray( arguments.extraInfo.tagContext )
			) {
				var frames            = arguments.extraInfo.tagContext;
				exception.totalFrames = frames.len();

				// Find application code that may appear below many framework frames.
				var actionable = frameClassifier.findFirstApplicationFrame( frames, variables.MAX_SCAN_FRAMES );

				var scanLimit = min( frames.len(), variables.MAX_SCAN_FRAMES );
				var lastKept  = 0;

				for ( var i = 1; i <= scanLimit; i++ ) {
					if ( exception.tagContext.len() >= settings.stackFrames ) {
						break;
					}

					var template = structKeyExists( frames[ i ], "template" ) ? frames[ i ].template : "";

					/* Skip database driver frames that are not file paths. Always keep the
					 * first frame because it marks the throw site. */
					if (
						i > 1 && template.len()
						&& ( template.find( "|" ) || ( !template.find( "/" ) && !template.find( "\" ) ) )
					) {
						continue;
					}

					exception.tagContext.append( frameStruct( frames[ i ], i, template ) );
					lastKept = i;
				}

				// Add the application frame even when it falls past the display limit.
				if ( !actionable.isEmpty() ) {
					exception.actionableFrame = {
						index    : actionable.index,
						template : relativeTemplate( actionable.template ),
						line     : actionable.line
					};

					if ( actionable.index > lastKept ) {
						exception.tagContext.append(
							frameStruct( frames[ actionable.index ], actionable.index, actionable.template )
						);
					}

					// Add source for the application frame as well as the throw site.
					if ( settings.codeSnippetLines && actionable.index > 1 ) {
						exception.callerSnippet = snippetFor( actionable.template, actionable.line );
					}
				}

				exception.omittedFrames = max( 0, exception.totalFrames - exception.tagContext.len() );
			}

			return exception;
		} catch ( any e ) {
			return {};
		}
	}

	/**
	 * firstOf
	 *
	 * Returns the first requested key that exists and has a value.
	 * Callers pass several keys because engines use different names for the same
	 * exception field. For example, Adobe uses errNumber instead of errorCode.
	 *
	 * @source The exception struct or object.
	 * @keys   Key names to try, in order.
	 */
	private string function firstOf( required any source, required array keys ){
		for ( var key in arguments.keys ) {
			try {
				if ( !structKeyExists( arguments.source, key ) ) {
					continue;
				}
				var value = arguments.source[ key ];
				if ( isSimpleValue( value ) && toString( value ).trim().len() ) {
					return toString( value );
				}
			} catch ( any e ) {
			}
		}
		return "";
	}

	/**
	 * frameStruct
	 *
	 * Converts a raw stack frame to the fields used in an alert.
	 * Engines use different keys for the function name. Lucee uses "??" when a
	 * function name is not available.
	 *
	 * @frame    The raw tagContext frame struct.
	 * @index    The frame's position in the raw tagContext array.
	 * @template The frame's template path, already extracted by the caller.
	 */
	private struct function frameStruct(
		required any frame,
		required numeric index,
		required string template
	){
		var fn = firstOf( arguments.frame, [ "function", "functionName", "id" ] );
		if ( fn == "??" ) {
			fn = "";
		}

		return {
			template    : arguments.template.len() ? relativeTemplate( arguments.template ) : "",
			line        : structKeyExists( arguments.frame, "line" ) ? arguments.frame.line : 0,
			index       : arguments.index,
			application : arguments.template.len() ? frameClassifier.isApplicationFrame( arguments.template ) : false,
			fn          : fn
		};
	}

	/**
	 * buildDatabaseDetail
	 *
	 * Returns the SQL, datasource, and driver codes from a database exception.
	 * Returns an empty struct for other exception types. SQL is limited to 2,000
	 * characters because generated statements can be very large.
	 *
	 * @extraInfo The exception struct or object.
	 */
	private struct function buildDatabaseDetail( required any extraInfo ){
		var detail = structNew( "ordered" );

		try {
			var sql = firstOf( arguments.extraInfo, [ "sql" ] );
			if ( sql.len() ) {
				detail[ "sql" ] = truncate( sql, 2000 );
			}

			// An ordered struct keeps this label order and case on Adobe.
			var fields = structNew( "ordered" );
			fields[ "datasource" ]      = [ "datasource", "dataSource" ];
			fields[ "queryError" ]      = [ "queryError" ];
			fields[ "sqlState" ]        = [ "sqlState", "SQLState" ];
			fields[ "nativeErrorCode" ] = [ "nativeErrorCode" ];
			fields[ "additional" ]      = [ "additional" ];

			/* Bound SQL values can help reproduce a query error. They can also hold
			 * user input. maskKeys cannot hide them because they have no field names. */
			if ( settings.includeQueryParams ) {
				fields[ "params" ] = [ "where" ];
			}

			for ( var name in fields ) {
				var value = firstOf( arguments.extraInfo, fields[ name ] );
				if ( value.len() ) {
					detail[ name ] = truncate( value, settings.rcValueMaxLength );
				}
			}
		} catch ( any e ) {
		}

		return detail;
	}

	/**
	 * buildSnippet
	 *
	 * Returns source lines around the line that threw.
	 * The file is read directly because Adobe does not provide the codePrintPlain
	 * excerpt that Lucee and BoxLang provide. Returns no lines when snippets are
	 * disabled or the source file cannot be read.
	 *
	 * @extraInfo The exception struct or object.
	 */
	private struct function buildSnippet( required any extraInfo ){
		var snippet = { template : "", line : 0, lines : [] };

		if ( !settings.codeSnippetLines ) {
			return snippet;
		}

		try {
			if (
				!structKeyExists( arguments.extraInfo, "tagContext" )
				|| !isArray( arguments.extraInfo.tagContext )
				|| !arguments.extraInfo.tagContext.len()
			) {
				return snippet;
			}

			var frame    = arguments.extraInfo.tagContext[ 1 ];
			var template = structKeyExists( frame, "template" ) ? frame.template : "";
			var line     = structKeyExists( frame, "line" ) ? val( frame.line ) : 0;

			return snippetFor( template, line );
		} catch ( any e ) {
		}

		return snippet;
	}

	/**
	 * snippetFor
	 *
	 * Reads source lines around one file position.
	 * Both source snippets use this method so they share the same checks and
	 * limits. A missing or unreadable file returns an empty snippet.
	 *
	 * @template Absolute path of the file to read.
	 * @line     The line to center the excerpt on.
	 */
	private struct function snippetFor( required string template, required numeric line ){
		var snippet = { template : "", line : 0, lines : [] };

		try {
			if ( !arguments.template.len() || arguments.line <= 0 || !fileExists( arguments.template ) ) {
				return snippet;
			}

			snippet.template = relativeTemplate( arguments.template );
			snippet.line     = arguments.line;
			snippet.lines    = readLines( arguments.template, arguments.line );
		} catch ( any e ) {
		}

		return snippet;
	}

	/**
	 * readLines
	 *
	 * Reads a limited range around one source line.
	 * Reading stops after the range. Each line is limited so generated code cannot
	 * fill the email. Lines after 10,000 are skipped to avoid reading a huge file.
	 *
	 * @template  Absolute path of the file to read.
	 * @errorLine The line that threw.
	 */
	private array function readLines( required string template, required numeric errorLine ){
		var lines   = [];
		var context = settings.codeSnippetLines;
		var first   = max( 1, arguments.errorLine - context );
		var last    = arguments.errorLine + context;
		var file    = "";

		if ( arguments.errorLine > 10000 ) {
			return lines;
		}

		try {
			file       = fileOpen( arguments.template, "read" );
			var number = 0;

			while ( !fileIsEOF( file ) ) {
				var text = fileReadLine( file );
				number++;

				if ( number < first ) {
					continue;
				}
				if ( number > last ) {
					break;
				}

				lines.append( {
					number  : number,
					text    : truncate( text, 300 ),
					isError : number == arguments.errorLine
				} );
			}
		} catch ( any e ) {
		} finally {
			try {
				if ( isObject( file ) ) {
					fileClose( file );
				}
			} catch ( any e ) {
			}
		}

		return lines;
	}

	/**
	 * buildCauses
	 *
	 * Returns the type, message, and detail from each exception in the cause chain.
	 * The walk stops after five levels to prevent a loop.
	 *
	 * @extraInfo The exception struct or object.
	 */
	private array function buildCauses( required any extraInfo ){
		var causes  = [];
		var current = arguments.extraInfo;

		try {
			for ( var i = 1; i <= 5; i++ ) {
				if ( !structKeyExists( current, "cause" ) ) {
					break;
				}

				current = current.cause;

				if ( !( isStruct( current ) || isObject( current ) ) ) {
					break;
				}

				var type    = firstOf( current, [ "type" ] );
				var message = firstOf( current, [ "message" ] );

				if ( !type.len() && !message.len() ) {
					break;
				}

				causes.append( {
					type    : type,
					message : truncate( message, 500 ),
					detail  : truncate( firstOf( current, [ "detail" ] ), 500 )
				} );
			}
		} catch ( any e ) {
		}

		return causes;
	}

	/**
	 * buildRequest
	 *
	 * Returns the origin, ColdBox route, and selected request values.
	 * Missing request values use settings.emptyValueText. The user and sessionId
	 * rows only appear when their features are active.
	 *
	 * A request outside ColdBox gets one coldbox row instead of routing rows.
	 * If reading the request context fails, keep the routing rows and fill any
	 * missing values with placeholders. This shows the failure in the email.
	 *
	 * @exception The already-built exception struct, used to find the origin.
	 */
	private struct function buildRequest( struct exception = {} ){
		var info = structNew( "ordered" );

		addValue( info, "origin", buildOrigin( arguments.exception ) );

		// Build a complete method and URL that a developer can copy.
		addValue( info, "url", requestUrl() );

		// Only when the application configured a userProvider closure.
		if ( !isSimpleValue( settings.userProvider ) ) {
			addValue( info, "user", buildUser() );
		}

		try {
			if ( hasColdBoxContext() ) {
				var event = coldbox.getRequestService().getContext();
				addValue( info, "event", event.getCurrentEvent() );
				// A routed URL sets this value. An index.cfm?event= request does not.
				addValue( info, "route", event.getCurrentRoutedUrl() );
				// Show the route pattern that matched the current URL.
				addValue( info, "routePattern", event.getCurrentRoute() );
				addValue( info, "routeName", event.getCurrentRouteName() );
				addValue( info, "routedModule", event.getCurrentRoutedModule() );
				addValue( info, "routedNamespace", event.getCurrentRoutedNamespace() );
				// How far rendering got before the error.
				addValue( info, "view", event.getCurrentView() );
				addValue( info, "layout", event.getCurrentLayout() );
				// Record whether the caller was an Ajax request.
				addValue( info, "isAjax", event.isAjax() ? "yes" : "no" );
			} else {
				// Requests outside ColdBox have no routing details to show.
				addValue( info, "coldbox", "not a ColdBox request" );
			}
		} catch ( any e ) {
			// Fill missing keys without replacing values that were already read.
			var routingKeys = [
				"event",
				"route",
				"routePattern",
				"routeName",
				"routedModule",
				"routedNamespace",
				"view",
				"layout",
				"isAjax"
			];
			for ( var routingKey in routingKeys ) {
				if ( !info.keyExists( routingKey ) ) {
					addValue( info, routingKey, "" );
				}
			}
		}

		// These values identify the server and whether this was a web request.
		addValue( info, "machine", machineName() );
		addValue( info, "context", executionContext() );
		addValue( info, "memory", memoryUsage() );
		// Record how long the request ran before it failed.
		addValue( info, "elapsed", elapsedMs() );

		if ( settings.includeScopes.keyExists( "session" ) && settings.includeScopes.session ) {
			addValue( info, "sessionId", sessionIdentifier() );
		}

		if ( settings.includeScopes.cgi ) {
			try {
				addValue( info, "method", cgi.request_method );
				addValue( info, "templatePath", cgi.cf_template_path );
				addValue( info, "path", cgi.path_info );
				addValue( info, "queryString", queryStringValue() );
				addValue( info, "host", cgi.http_host );
				addValue( info, "referer", cgi.http_referer );
				addValue( info, "remoteAddr", cgi.remote_addr );
				// A proxy may provide the original client address and URL scheme.
				addValue( info, "forwardedFor", cgi.http_x_forwarded_for );
				addValue( info, "forwardedProto", cgi.http_x_forwarded_proto );
				addValue( info, "userAgent", cgi.http_user_agent );
				// The Accept header helps identify browsers, bots, and API clients.
				addValue( info, "accept", cgi.http_accept );
				addValue( info, "acceptLanguage", cgi.http_accept_language );
				addValue( info, "https", cgi.https );
				addValue( info, "serverPort", cgi.server_port );
				addValue( info, "serverName", cgi.server_name );
			} catch ( any e ) {
			}
		}

		// Add the request headers selected in includeHeaders.
		if ( isArray( settings.includeHeaders ) && settings.includeHeaders.len() ) {
			try {
				var headers = buildHeaders( getHTTPRequestData( false ).headers );
				for ( var headerName in headers ) {
					addValue( info, headerName, headers[ headerName ] );
				}
			} catch ( any e ) {
			}
		}

		return info;
	}

	/**
	 * buildUser
	 *
	 * Calls the application's userProvider closure and returns its display text.
	 * The closure receives WireBox, so it can use any authentication library.
	 * A missing, invalid, or failing provider returns an empty string.
	 */
	private string function buildUser(){
		try {
			var provider = settings.userProvider;

			// Engines do not agree on which function reports every closure.
			if ( isSimpleValue( provider ) || !( isClosure( provider ) || isCustomFunction( provider ) ) ) {
				return "";
			}

			var result = provider( coldbox.getWireBox() );
			return isNull( result ) || !isSimpleValue( result ) ? "" : toString( result );
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * sessionIdentifier
	 *
	 * Returns a session ID that can connect alerts from the same visitor.
	 * The servlet session ID takes priority over CFID and CFTOKEN.
	 *
	 * This is off by default because a live session ID may allow impersonation.
	 */
	private string function sessionIdentifier(){
		if ( !settings.includeScopes.keyExists( "session" ) || !settings.includeScopes.session ) {
			return "";
		}

		try {
			if ( !isDefined( "session" ) ) {
				return "";
			}
			if ( session.keyExists( "sessionId" ) ) {
				return toString( session.sessionId );
			}
			if ( session.keyExists( "cfid" ) && session.keyExists( "cftoken" ) ) {
				return "CFID=#session.cfid# CFTOKEN=#session.cftoken#";
			}
		} catch ( any e ) {
		}

		return "";
	}

	/**
	 * machineName
	 *
	 * Returns the host name of the server that handled the error.
	 * serverName is the host requested by the client. Several servers may answer
	 * for that name behind a load balancer. The result is cached because the
	 * lookup may use DNS.
	 */
	private string function machineName(){
		if ( variables.keyExists( "cachedMachineName" ) ) {
			return variables.cachedMachineName;
		}

		var name = "";
		try {
			name = createObject( "java", "java.net.InetAddress" )
				.getLocalHost()
				.getHostName();
		} catch ( any e ) {
		}

		// Cache only a real name, so one failed DNS lookup at startup does not
		// blank the machine row for the life of the application.
		if ( name.len() ) {
			variables.cachedMachineName = name;
		}

		return name;
	}

	/**
	 * executionContext
	 *
	 * Describes the request or background thread that produced the error.
	 * The Java thread name can connect an alert to an engine log. Only an HTTP
	 * request has cgi.request_method.
	 */
	private string function executionContext(){
		var threadName = "";

		try {
			threadName = createObject( "java", "java.lang.Thread" ).currentThread().getName();
		} catch ( any e ) {
		}

		var suffix = threadName.len() ? " (#threadName#)" : "";

		try {
			if ( cgi.request_method.trim().len() ) {
				return "web request#suffix#";
			}
		} catch ( any e ) {
		}

		if ( threadName.findNoCase( "scheduler" ) || threadName.findNoCase( "task" ) ) {
			return "scheduled task#suffix#";
		}

		return threadName.len() ? "background thread#suffix#" : "";
	}

	/**
	 * memoryUsage
	 *
	 * Reports JVM heap use when the error occurred.
	 * This can show whether memory pressure contributed to an OutOfMemoryError.
	 */
	private string function memoryUsage(){
		try {
			var runtime = createObject( "java", "java.lang.Runtime" ).getRuntime();
			var used    = int( ( runtime.totalMemory() - runtime.freeMemory() ) / 1048576 );
			var maxHeap = int( runtime.maxMemory() / 1048576 );
			return "#used# MB used of #maxHeap# MB max";
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * elapsedMs
	 *
	 * Returns how many milliseconds the request ran before the error.
	 * Lucee and BoxLang provide the start time. Adobe does not, so Adobe returns
	 * an empty string.
	 */
	private string function elapsedMs(){
		try {
			var start = getPageContext().getStartTime();
			if ( isNumeric( start ) && start > 0 ) {
				return "#max( 0, getTickCount() - start )# ms";
			}
		} catch ( any e ) {
		}
		return "";
	}

	/**
	 * requestUrl
	 *
	 * Returns a method and URL that can be copied to reproduce the request.
	 * queryStringValue() applies the masking setting. X-Forwarded-Proto provides
	 * the original scheme when a proxy changes cgi.https.
	 *
	 * Returns an empty string outside a web request.
	 */
	private string function requestUrl(){
		try {
			var method = cgi.request_method.trim();
			var host   = cgi.http_host.trim();
			if ( !method.len() || !host.len() ) {
				return "";
			}

			var scheme = cgi.http_x_forwarded_proto.trim().len()
			 ? cgi.http_x_forwarded_proto.trim()
			 : ( cgi.https.trim().lcase() == "on" ? "https" : "http" );
			var path = cgi.path_info.trim().len() ? cgi.path_info : cgi.script_name;
			var qs   = queryStringValue();

			return "#method.ucase()# #scheme#://#host##path##( qs.len() ? "?" & qs : "" )#";
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * runtimeInfo
	 *
	 * Returns version details for the email's Runtime section.
	 * The result is cached because the versions do not change while the
	 * application runs.
	 *
	 * BoxLang and Lucee also define server.coldfusion for compatibility. Their
	 * engine-specific keys are checked first. Unavailable values are omitted.
	 */
	private struct function runtimeInfo(){
		if ( variables.keyExists( "cachedRuntimeInfo" ) ) {
			return variables.cachedRuntimeInfo;
		}

		var info = structNew( "ordered" );

		try {
			if ( server.keyExists( "boxlang" ) ) {
				info[ "engine" ] = "BoxLang #server.boxlang.version#";
			} else if ( server.keyExists( "lucee" ) ) {
				info[ "engine" ] = "Lucee #server.lucee.version#";
			} else if ( server.keyExists( "coldfusion" ) ) {
				info[ "engine" ] = "#server.coldfusion.productName# #server.coldfusion.productVersion#";
			}
		} catch ( any e ) {
		}

		try {
			info[ "java" ] = server.java.version;
		} catch ( any e ) {
			try {
				info[ "java" ] = createObject( "java", "java.lang.System" ).getProperty( "java.version" );
			} catch ( any inner ) {
			}
		}

		try {
			var coldboxVersion = coldbox.getColdBoxSetting( "version" );
			if ( isSimpleValue( coldboxVersion ) && coldboxVersion.len() ) {
				info[ "coldbox" ] = coldboxVersion;
			}
		} catch ( any e ) {
		}

		var ownVersion = moduleVersion();
		if ( ownVersion.len() ) {
			info[ "errorAlerts" ] = ownVersion;
		}

		variables.cachedRuntimeInfo = info;
		return info;
	}

	/**
	 * buildHeaders
	 *
	 * Returns the headers named in settings.includeHeaders, in the same order.
	 * Header name matching ignores case. Values pass through the masking and
	 * length limits.
	 *
	 * Credential headers are blocked even when the application lists them.
	 *
	 * @rawHeaders The headers struct from getHTTPRequestData( false ).
	 */
	private struct function buildHeaders( required struct rawHeaders ){
		var result = structNew( "ordered" );
		var never  = [ "cookie", "authorization", "proxy-authorization" ];

		try {
			for ( var wanted in settings.includeHeaders ) {
				if ( !isSimpleValue( wanted ) || !wanted.trim().len() || never.findNoCase( wanted.trim() ) ) {
					continue;
				}
				for ( var key in arguments.rawHeaders ) {
					if ( key.compareNoCase( wanted.trim() ) == 0 ) {
						result[ wanted.trim() ] = sanitizeValue( wanted.trim(), arguments.rawHeaders[ key ] );
						break;
					}
				}
			}
		} catch ( any e ) {
		}

		return result;
	}

	/**
	 * buildRequestBody
	 *
	 * Reads the raw HTTP body and passes it to buildBody().
	 * Keeping the conversion separate lets tests run without a real request.
	 */
	private string function buildRequestBody(){
		try {
			return buildBody( getHTTPRequestData( true ) );
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * buildBody
	 *
	 * Converts a raw request body to text that can be included in an email.
	 *
	 * Form posts are skipped because rc already contains their masked fields.
	 * JSON objects and arrays pass through sanitizeNode(). Binary content shows
	 * only its size.
	 *
	 * A body accepted by isJSON() is never printed without masking. A body that
	 * is too large, fails to parse, or parses to a simple value is reported by
	 * size instead.
	 *
	 * Non-JSON text is truncated and shown as sent because it has no field names
	 * to mask. Engines disagree about malformed JSON. Adobe may treat text as
	 * non-JSON when Lucee or BoxLang accepts it as JSON.
	 *
	 * @httpData The struct from getHTTPRequestData( true ): headers plus content.
	 */
	private string function buildBody( required struct httpData ){
		try {
			var contentType = "";
			if ( structKeyExists( arguments.httpData, "headers" ) ) {
				for ( var key in arguments.httpData.headers ) {
					if ( key.compareNoCase( "content-type" ) == 0 ) {
						contentType = toString( arguments.httpData.headers[ key ] );
						break;
					}
				}
			}

			if (
				contentType.findNoCase( "application/x-www-form-urlencoded" )
				|| contentType.findNoCase( "multipart/form-data" )
			) {
				return "";
			}

			if ( !structKeyExists( arguments.httpData, "content" ) ) {
				return "";
			}

			var content = arguments.httpData.content;

			if ( isBinary( content ) ) {
				return "[binary, #len( content )# bytes]";
			}

			content = toString( content );
			if ( !content.trim().len() ) {
				return "";
			}

			if ( isJSON( content ) ) {
				// Avoid building a large value in memory while handling an error.
				if ( content.len() > variables.MAX_PARSE_CHARS ) {
					return "[body too large to mask, #content.len()# chars]";
				}

				try {
					var parsed = parseJson( content );
					if ( isStruct( parsed ) || isArray( parsed ) ) {
						ensureCompiled();
						var cleanBody = sanitizeNode(
							"",
							parsed,
							newSanitizeState( settings.requestBodyMaxLength, settingOr( "longValueMaxLength", 500 ) ),
							0
						);
						return truncate( serializeJSON( cleanBody ), settings.requestBodyMaxLength );
					}
				} catch ( any e ) {
				}

				/* The JSON could not be walked or had no field names. Report its size
				 * instead of printing content that did not pass the mask check. */
				return "[body could not be parsed for masking, #content.len()# chars]";
			}

			// Non-JSON text has no field names for maskKeys, so show it as sent.
			return truncate( content, settings.requestBodyMaxLength );
		} catch ( any e ) {
			return "";
		}
	}

	/**
	 * addValue
	 *
	 * Adds a key, substituting settings.emptyValueText when the value is null,
	 * blank, or only whitespace. Values that are not strings are converted first.
	 *
	 * @info  The ordered struct being built.
	 * @key   The key to add.
	 * @value The value to add.
	 */
	private void function addValue( required struct info, required string key, any value ){
		var text = "";

		if ( !isNull( arguments.value ) ) {
			try {
				text = isSimpleValue( arguments.value ) ? toString( arguments.value ) : "";
			} catch ( any e ) {
			}
		}

		arguments.info[ arguments.key ] = text.trim().len() ? text : settings.emptyValueText;
	}

	/**
	 * queryStringValue
	 *
	 * Returns the query string, masked when settings.maskQueryString is on.
	 */
	private string function queryStringValue(){
		return settings.maskQueryString ? maskQueryString( cgi.query_string ) : cgi.query_string;
	}

	/**
	 * buildOrigin
	 *
	 * Returns the file and line that produced the error, as `template:line`.
	 *
	 * An exception uses its first stack frame. A plain log.error() call uses the
	 * first live stack frame outside this module and LogBox. Returns an empty
	 * string when neither frame is available.
	 *
	 * @exception The built exception struct, empty when extraInfo was not an exception.
	 */
	private string function buildOrigin( required struct exception ){
		try {
			if (
				arguments.exception.keyExists( "tagContext" )
				&& arguments.exception.tagContext.len()
			) {
				var top = arguments.exception.tagContext[ 1 ];
				return "#top.template#:#top.line#";
			}
		} catch ( any e ) {
		}

		return callerFrame();
	}

	/**
	 * callerFrame
	 *
	 * Returns the first application frame from the live call stack.
	 * Frames from this module and LogBox are skipped because they are part of the
	 * alert process rather than the original logging call.
	 *
	 * Returns an empty string when the live stack is unavailable.
	 */
	private string function callerFrame(){
		try {
			var stack = callStackGet();
			for ( var frame in stack ) {
				if ( !structKeyExists( frame, "template" ) || !frame.template.len() ) {
					continue;
				}
				var template = frame.template.replace( "\", "/", "all" );
				// Skip alerting code so the result points to the original caller.
				if (
					template.findNoCase( variables.ownModelsPath )
					|| template.findNoCase( variables.ownInterceptorsPath )
					|| template.findNoCase( "/coldbox/system/logging/" )
				) {
					continue;
				}
				var line = structKeyExists( frame, "lineNumber" ) ? frame.lineNumber : 0;
				return "#relativeTemplate( frame.template )#:#line#";
			}
		} catch ( any e ) {
		}
		return "";
	}

	/**
	 * relativeTemplate
	 *
	 * Removes the application root from a file path when relativePaths is on.
	 * Paths outside the application root stay unchanged.
	 *
	 * @template The absolute file path from a stack frame.
	 */
	private string function relativeTemplate( required string template ){
		if ( !settings.relativePaths ) {
			return arguments.template;
		}

		try {
			var root = coldbox.getAppRootPath().replace( "\", "/", "all" );
			var path = arguments.template.replace( "\", "/", "all" );
			if ( root.len() && path.findNoCase( root ) == 1 ) {
				return "/" & path.removeChars( 1, root.len() );
			}
			return path;
		} catch ( any e ) {
			return arguments.template;
		}
	}

	/**
	 * maskQueryString
	 *
	 * Masks matching field values in a query string.
	 * Without this step, the rc table could hide a value while the raw URL still
	 * exposed it.
	 *
	 * @queryString The raw cgi.query_string value.
	 */
	private string function maskQueryString( required string queryString ){
		if ( !arguments.queryString.len() ) {
			return "";
		}

		ensureCompiled();

		var pairs = arguments.queryString.listToArray( "&" );
		var clean = [];

		for ( var pair in pairs ) {
			var name = pair.listFirst( "=" );

			// Decode field names before matching so URL encoding cannot bypass masking.
			var decoded = name;
			try {
				decoded = urlDecode( name );
			} catch ( any e ) {
			}

			// A pair without "=" has no value to hide, so it passes through.
			if ( pair.find( "=" ) && isMasked( decoded ) ) {
				clean.append( "#name#=#variables.MASK_TOKEN#" );
			} else {
				clean.append( pair );
			}
		}

		return clean.toList( "&" );
	}

	/**
	 * isMasked
	 *
	 * Returns true when the masking settings match a field name.
	 * maskKeys uses an exact match that ignores case. Exact matching prevents a
	 * key such as `token` from hiding `tokenCount`. Wildcard patterns are checked
	 * only when the exact lookup misses.
	 *
	 * Exact matches use a hash lookup. Pattern results are cached by field name
	 * because nested payloads often repeat the same names.
	 *
	 * @key The field name to test.
	 */
	private boolean function isMasked( required string key ){
		if ( !arguments.key.len() ) {
			return false;
		}
		ensureCompiled();

		var compiled = variables.maskCompiled;
		if ( structKeyExists( compiled.exactLookup, arguments.key ) ) {
			return true;
		}
		if ( !compiled.keyPatterns.len() ) {
			return false;
		}
		if ( structKeyExists( compiled.verdictCache, arguments.key ) ) {
			return compiled.verdictCache[ arguments.key ];
		}

		var masked = false;
		for ( var pattern in compiled.keyPatterns ) {
			if ( reFindNoCase( pattern, arguments.key ) ) {
				masked = true;
				break;
			}
		}
		if ( structCount( compiled.verdictCache ) < variables.VERDICT_CACHE_MAX ) {
			compiled.verdictCache[ arguments.key ] = masked;
		}
		return masked;
	}

	/**
	 * buildRc
	 *
	 * Returns a sanitized request collection.
	 * Use the ColdBox request collection when available. For a web request
	 * outside ColdBox, combine FORM and URL fields as ColdBox would.
	 * Return an empty struct if the collection cannot be built.
	 */
	private struct function buildRc(){
		try {
			return sanitizeScope(
				hasColdBoxContext()
				 ? coldbox.getRequestService().getContext().getCollection()
				 : scopeCollection()
			);
		} catch ( any e ) {
			return {};
		}
	}

	/**
	 * hasColdBoxContext
	 *
	 * Checks whether ColdBox routed the current request.
	 * Check contextExists() before calling getContext(), because getContext()
	 * creates a context if one is missing. Then check for a non-empty event name.
	 * Code outside ColdBox can create an empty context by calling WireBox.
	 * That empty context does not count as a ColdBox request. Keep this method
	 * identical to the copy in CaptureService.
	 */
	private boolean function hasColdBoxContext(){
		var requestService = coldbox.getRequestService();
		if ( !requestService.contextExists() ) {
			return false;
		}
		return requestService.getContext().getCurrentEvent().len() > 0;
	}

	/**
	 * scopeCollection
	 *
	 * Returns the merged FORM and URL scopes for a request outside ColdBox.
	 * URL values replace FORM values with the same key, as in ColdBox's
	 * requestCapture(). Return an empty struct when there is no web request,
	 * such as for a scheduled task or a background thread.
	 *
	 * Keep this in a separate method so tests can supply fields without changing
	 * the test runner's FORM and URL scopes.
	 */
	private struct function scopeCollection(){
		var collection = {};

		try {
			if ( !cgi.request_method.trim().len() ) {
				return collection;
			}
			structAppend( collection, form );
			structAppend( collection, url );
		} catch ( any e ) {
			return {};
		}

		return collection;
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
	 *
	 * Masking checks the key before converting the value. This prevents a secret
	 * from reaching serialized email content. maskKeys matches exact names, while
	 * maskKeyPatterns provides optional wildcard matching.
	 *
	 * Complex values pass through sanitizeNode() so nested keys are also checked.
	 * A null value becomes a placeholder instead of causing the rc table to fail.
	 *
	 * @key   The scope key, checked against the masking configuration.
	 * @value The value to sanitize, any type, may be null.
	 */
	private string function sanitizeValue( required string key, any value ){
		ensureCompiled();

		if ( isNull( arguments.value ) ) {
			return "[null]";
		}

		if ( isObject( arguments.value ) ) {
			// Some objects report isStruct(), so exclude objects before walking data.
			if ( isMasked( arguments.key ) ) {
				return variables.MASK_TOKEN;
			}
			try {
				return "[object #getMetadata( arguments.value ).name#]";
			} catch ( any e ) {
				return "[object]";
			}
		}

		var clean = sanitizeNode(
			arguments.key,
			arguments.value,
			newSanitizeState( settings.rcValueMaxLength, settings.rcValueMaxLength ),
			0
		);

		// Serialize containers only. Simple values already include any size label.
		return isSimpleValue( clean ) ? clean : stringify( clean, settings.rcValueMaxLength );
	}

	/**
	 * sanitizeDeep
	 *
	 * Returns a copy with matching keys masked at every visited level.
	 * The method walks structs and arrays. Objects and queries stay unchanged and
	 * are handled later by the serializer and output limit.
	 *
	 * RestHandler can place request headers inside extraInfo. This walk prevents
	 * a configured secret field from bypassing the Request section's checks.
	 *
	 * The walk stops after collecting enough content for extraInfoMaxLength.
	 * Individual strings use longValueMaxLength unless their key is exempt.
	 *
	 * A failure returns a placeholder instead of unchecked original content.
	 *
	 * @value The value to sanitize, any type.
	 */
	private any function sanitizeDeep( required any value ){
		ensureCompiled();
		return sanitizeNode(
			"",
			arguments.value,
			newSanitizeState( settingOr( "extraInfoMaxLength", 2000 ), settingOr( "longValueMaxLength", 500 ) ),
			0
		);
	}

	/**
	 * sanitizeNode
	 *
	 * Recursively converts one value to content that can be included in email.
	 * A matching key becomes the mask token before its value is read. Strings use
	 * sanitizeString(). Structs and arrays stop at the depth or character limit.
	 * Omitted entries are counted without being read. Objects, queries, and other
	 * values pass through to the caller's serializer.
	 *
	 * A failed node becomes a placeholder. Other values can still be included.
	 *
	 * @keyName The key this value sits under; "" for roots and array items.
	 * @value   The value to sanitize, any type, may be null.
	 * @state   The shared walk state from newSanitizeState().
	 * @depth   The current nesting level, capped at MAX_DEPTH.
	 */
	private any function sanitizeNode(
		required string keyName,
		any value,
		required struct state,
		numeric depth = 0
	){
		try {
			if ( arguments.depth > variables.MAX_DEPTH ) {
				return "[nested too deep]";
			}
			if ( arguments.state.remaining <= 0 ) {
				return "[omitted, size limit]";
			}
			if ( variables.maskCompiled.hasMaskConfig && isMasked( arguments.keyName ) ) {
				arguments.state.remaining -= arguments.keyName.len() + variables.MASK_TOKEN.len() + variables.NODE_OVERHEAD;
				return variables.MASK_TOKEN;
			}
			if ( isNull( arguments.value ) ) {
				arguments.state.remaining -= variables.NODE_OVERHEAD;
				return "[null]";
			}
			if ( isBinary( arguments.value ) ) {
				arguments.state.remaining -= arguments.keyName.len() + 24 + variables.NODE_OVERHEAD;
				return "[binary, #len( arguments.value )# bytes]";
			}
			if ( isSimpleValue( arguments.value ) ) {
				return sanitizeString( arguments.keyName, toString( arguments.value ), arguments.state, arguments.depth );
			}

			if ( isArray( arguments.value ) ) {
				var cleanList  = [];
				var totalItems = arguments.value.len();
				for ( var i = 1; i <= totalItems; i++ ) {
					if ( arguments.state.remaining <= 0 ) {
						cleanList.append( "[#totalItems - i + 1# more items]" );
						break;
					}
					cleanList.append(
						!arrayIsDefined( arguments.value, i )
						 ? "[null]"
						 : sanitizeNode( "", arguments.value[ i ], arguments.state, arguments.depth + 1 )
					);
				}
				arguments.state.remaining -= variables.NODE_OVERHEAD;
				return cleanList;
			}

			/* Check isObject() first because some objects also report isStruct().
			 * Objects, queries, XML, and other values pass through to the final
			 * serializer and length limit. */
			if ( isObject( arguments.value ) || !isStruct( arguments.value ) ) {
				arguments.state.remaining -= variables.NODE_OVERHEAD;
				return arguments.value;
			}

			var clean     = structNew( "ordered" );
			var totalKeys = structCount( arguments.value );
			var visited   = 0;
			for ( var key in arguments.value ) {
				if ( arguments.state.remaining <= 0 ) {
					clean[ "..." ] = "[#totalKeys - visited# more keys]";
					break;
				}
				visited++;
				// Display a short key, but use its full name for the mask check.
				var displayKey = key.len() > 200 ? key.left( 197 ) & "…" : key;
				clean[ displayKey ] = isNull( arguments.value[ key ] )
				 ? "[null]"
				 : sanitizeNode( key, arguments.value[ key ], arguments.state, arguments.depth + 1 );
			}
			arguments.state.remaining -= variables.NODE_OVERHEAD;
			return clean;
		} catch ( any e ) {
			return "[value could not be sanitized]";
		}
	}

	/**
	 * sanitizeString
	 *
	 * Limits one simple value and charges its size to the shared budget.
	 * Root values and exempt keys use the complete output limit. Other values use
	 * the per-value limit. Truncated values include their original size.
	 *
	 * len() and left() avoid copying more characters than the limit allows.
	 *
	 * @keyName The key the value sits under, used for the exemption lookup.
	 * @text    The value as a string.
	 * @state   The shared walk state from newSanitizeState().
	 * @depth   The current nesting level; 0 means the root of the pass.
	 */
	private string function sanitizeString(
		required string keyName,
		required string text,
		required struct state,
		required numeric depth
	){
		var totalLength = arguments.text.len();
		var isExempt    = arguments.keyName.len()
			&& structKeyExists( variables.maskCompiled.exemptLookup, arguments.keyName );
		var cap = ( isExempt || arguments.depth == 0 || arguments.state.valueCap == 0 )
			? arguments.state.contextCap
			: arguments.state.valueCap;

		var kept = arguments.text;
		if ( totalLength > cap ) {
			kept = arguments.text.left( cap ) & "… [truncated, #totalLength# chars total]";
		}

		arguments.state.remaining -= arguments.keyName.len() + kept.len() + variables.NODE_OVERHEAD;
		return kept;
	}

	/**
	 * newSanitizeState
	 *
	 * Builds the mutable state shared by one recursive sanitize pass.
	 * CFML passes the struct by reference, so every level uses the same budget.
	 *
	 * @budget   Total characters this pass may collect. Matches the caller's
	 *           final output cap: serializing only adds characters, so
	 *           collecting this much guarantees the final clip is reached.
	 * @valueCap Per-value cap for simple values, from longValueMaxLength.
	 */
	private struct function newSanitizeState( required numeric budget, required numeric valueCap ){
		return {
			remaining  : arguments.budget,
			contextCap : arguments.budget,
			valueCap   : arguments.valueCap
		};
	}

	/**
	 * ensureCompiled
	 *
	 * Compiles masking when no compiled configuration exists.
	 * build() checks for settings changes once per alert. This smaller check also
	 * supports tests that call sanitizer methods without calling build().
	 */
	private void function ensureCompiled(){
		if ( !structKeyExists( variables, "maskCompiled" ) ) {
			ensureMaskConfig();
		}
	}

	/**
	 * ensureMaskConfig
	 *
	 * Compiles masking when the settings fingerprint changes.
	 * build() calls this once per alert. The fingerprint supports tests that
	 * replace settings between calls. Two threads may compile the same result,
	 * which is safe because both assignments are equal.
	 */
	private void function ensureMaskConfig(){
		var fingerprint = settingOr( "maskKeys", [] ).toList( "|" )
			& "##" & settingOr( "maskKeyPatterns", [] ).toList( "|" )
			& "##" & settingOr( "longValueExemptKeys", [] ).toList( "|" );

		if (
			!structKeyExists( variables, "maskCompiled" )
			|| variables.maskCompiled.fingerprint != fingerprint
		) {
			variables.maskCompiled = compileMaskConfig( fingerprint );
		}
	}

	/**
	 * compileMaskConfig
	 *
	 * Builds the lookup state used by the sanitizer:
	 *
	 * - exactLookup stores maskKeys for a fast, case-insensitive hash lookup.
	 * - keyPatterns stores compiled wildcard regular expressions.
	 * - exemptLookup stores longValueExemptKeys.
	 * - verdictCache stores pattern results by field name.
	 * - hasMaskConfig lets the walker skip checks when masking is not configured.
	 *
	 * @fingerprint The fingerprint string identifying this configuration.
	 */
	private struct function compileMaskConfig( required string fingerprint ){
		var compiled = {
			fingerprint   : arguments.fingerprint,
			exactLookup   : {},
			keyPatterns   : [],
			exemptLookup  : {},
			verdictCache  : {},
			hasMaskConfig : false
		};

		for ( var key in settingOr( "maskKeys", [] ) ) {
			if ( key.len() ) {
				compiled.exactLookup[ key ] = true;
			}
		}
		for ( var pattern in settingOr( "maskKeyPatterns", [] ) ) {
			if ( pattern.len() ) {
				compiled.keyPatterns.append( wildcardToRegex( pattern ) );
			}
		}
		for ( var exempt in settingOr( "longValueExemptKeys", [] ) ) {
			if ( exempt.len() ) {
				compiled.exemptLookup[ exempt ] = true;
			}
		}
		compiled.hasMaskConfig = structCount( compiled.exactLookup ) > 0 || compiled.keyPatterns.len() > 0;

		return compiled;
	}

	/**
	 * wildcardToRegex
	 *
	 * Converts a wildcard pattern to a regular expression for the full key.
	 * Regular expression characters are escaped. Each * becomes ".*".
	 *
	 * @pattern The wildcard pattern from settings.maskKeyPatterns.
	 */
	private string function wildcardToRegex( required string pattern ){
		var escaped = reReplace( arguments.pattern, "([\\\.\[\]\(\)\+\?\^\$\|\{\}])", "\\\1", "all" );
		return "^" & escaped.replace( "*", ".*", "all" ) & "$";
	}

	/**
	 * settingOr
	 *
	 * Returns a module setting or a default value when the key is missing.
	 * This supports applications and test fixtures created before a setting was
	 * added.
	 *
	 * @name         The settings key to read.
	 * @defaultValue The value to use when the key is missing.
	 */
	private any function settingOr( required string name, required any defaultValue ){
		return structKeyExists( settings, arguments.name ) ? settings[ arguments.name ] : arguments.defaultValue;
	}

	/**
	 * stringify
	 *
	 * Converts a value to a limited string without throwing.
	 *
	 * If a struct cannot be converted as one value, its keys are converted one at
	 * a time. One unsupported value should not hide every readable sibling.
	 *
	 * @value     The value to serialize, any type.
	 * @maxLength The maximum length of the returned string.
	 */
	private string function stringify( required any value, required numeric maxLength ){
		try {
			if ( isSimpleValue( arguments.value ) ) {
				return truncate( toString( arguments.value ), arguments.maxLength );
			}
			return truncate( toJson( arguments.value ), arguments.maxLength );
		} catch ( any e ) {
			return truncate( salvageStruct( arguments.value ), arguments.maxLength );
		}
	}

	/**
	 * salvageStruct
	 *
	 * Rebuilds a failed struct conversion one key at a time.
	 * Readable values stay visible. An unreadable value becomes a marker. Values
	 * that are not plain structs use the original placeholder.
	 *
	 * @value The value whose conversion failed.
	 */
	private string function salvageStruct( required any value ){
		try {
			if ( isObject( arguments.value ) || !isStruct( arguments.value ) ) {
				return "[unserializable value]";
			}

			var pairs = [];
			for ( var key in arguments.value ) {
				// Serialize the key so the rebuilt text remains valid JSON.
				pairs.append( toJson( key ) & ":" & jsonOrMarker( arguments.value[ key ] ) );
			}
			return "{" & pairs.toList( "," ) & "}";
		} catch ( any e ) {
			return "[unserializable value]";
		}
	}

	/**
	 * jsonOrMarker
	 *
	 * Returns one value as JSON or a marker for an unsupported value.
	 * An object marker includes its type when the type is available.
	 *
	 * @value The value to convert, any type, may be null.
	 */
	private string function jsonOrMarker( any value ){
		if ( isNull( arguments.value ) ) {
			return toJson( "[null]" );
		}

		try {
			return toJson( arguments.value );
		} catch ( any e ) {
			// The conversion failed, so return a marker below.
		}

		if ( isObject( arguments.value ) ) {
			try {
				return toJson( "[object #getMetadata( arguments.value ).name#: could not be serialized]" );
			} catch ( any e ) {
				// The type name is unavailable, so report it without one.
			}
		}

		return toJson( "[value could not be serialized]" );
	}

	/**
	 * toJson
	 *
	 * Serializes one value.
	 * A separate method lets tests force a failure on every engine.
	 *
	 * @value The value to serialize, any type.
	 */
	private string function toJson( required any value ){
		return serializeJSON( arguments.value );
	}

	/**
	 * parseJson
	 *
	 * Deserializes one request body.
	 * A separate method lets tests force the same parse outcomes on every engine.
	 * Engines disagree about malformed JSON. For example, Adobe rejects a
	 * trailing comma that Lucee and BoxLang accept.
	 *
	 * @content The request body text.
	 */
	private any function parseJson( required string content ){
		return deserializeJSON( arguments.content );
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
