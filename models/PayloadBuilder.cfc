/**
 * PayloadBuilder
 *
 * Converts a LogBox event and available request data into a plain struct.
 * Request sections return empty values when no request context exists.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings"        inject="coldbox:moduleSettings:errorAlerts";
	property name="coldbox"         inject="coldbox";
	property name="frameClassifier" inject="FrameClassifier@errorAlerts";

	/**
	 * init
	 *
	 * Creates the LogLevels helper used for severity names, and records where
	 * this module's own code lives so callerFrame() can skip its own frames.
	 * The paths are computed instead of hard-coded because the module is not
	 * always installed at /modules/errorAlerts/ - the test harness loads it
	 * from the repo root, and apps can use modules_app or a custom location.
	 */
	function init(){
		variables.logLevels = new coldbox.system.logging.LogLevels();

		/* How many raw stack frames to inspect when looking for the application
		 * caller. A runaway recursive stack can hold thousands of frames, and
		 * scanning them all on every alert would be wasted work. */
		variables.MAX_SCAN_FRAMES = 100;

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
			payload.extraInfo = stringify( sanitizeDeep( arguments.logEvent.getExtraInfo() ), 2000 );
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
			// Which server flushed this digest. Behind a load balancer each
			// machine keeps its own throttle counts, so the digest is per-box.
			machine         : machineName(),
			moduleVersion   : moduleVersion()
		};

		// Distinct routes and client addresses ThrottleService sampled during
		// the window. Guarded so an older seed shape still builds.
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

				/* Find the first frame that belongs to the application itself.
				 * A database or ORM failure can bury the application's own code
				 * far below framework frames, past the display cut-off. */
				var actionable = frameClassifier.findFirstApplicationFrame( frames, variables.MAX_SCAN_FRAMES );

				var scanLimit = min( frames.len(), variables.MAX_SCAN_FRAMES );
				var lastKept  = 0;

				for ( var i = 1; i <= scanLimit; i++ ) {
					if ( exception.tagContext.len() >= settings.stackFrames ) {
						break;
					}

					var template = structKeyExists( frames[ i ], "template" ) ? frames[ i ].template : "";

					/* A database failure fills the stack with driver frames like
					 * "|SQLServer|6.0.0.1282|" - not file paths, nothing a
					 * developer can open. Skip any frame whose template contains a
					 * pipe or has no directory separator, since neither appears in
					 * a real path. The first frame always stays so the throw site
					 * is never hidden. */
					if (
						i > 1 && template.len()
						&& ( template.find( "|" ) || ( !template.find( "/" ) && !template.find( "\" ) ) )
					) {
						continue;
					}

					exception.tagContext.append( frameStruct( frames[ i ], i, template ) );
					lastKept = i;
				}

				/* When the application's own frame fell past the display cut-off,
				 * append it as one extra pinned frame so the email always shows
				 * which line of application code triggered the error. */
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

					// Second source excerpt: the application line that made the
					// call, next to the throw site the first snippet shows.
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
	 * Returns the first of the given keys that exists and has content, as a
	 * string. Engines name the same value differently — Adobe uses `errNumber`
	 * where others use `errorCode` — so callers pass every spelling.
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
	 * Returns one stack frame for the payload: display path, line, the raw
	 * tagContext position, whether the frame is application code, and the
	 * function name when the engine supplies one. Engines spell the function
	 * key differently, and Lucee fills `id` with "??" when it has no name.
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
	 * Returns the query-specific fields a database exception carries: the failing
	 * SQL, the datasource, and the driver's own error codes. Without these a query
	 * failure only reports the generic message and there is no way to tell which
	 * statement broke. Returns an empty struct for a non-database exception.
	 *
	 * The SQL is capped at 2,000 characters because a generated statement can be
	 * far longer than the whole email budget.
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

			// Ordered so the labels keep this order and their camelCase spelling.
			// A plain struct literal would come back uppercased on Adobe.
			var fields = structNew( "ordered" );
			fields[ "datasource" ]      = [ "datasource", "dataSource" ];
			fields[ "queryError" ]      = [ "queryError" ];
			fields[ "sqlState" ]        = [ "sqlState", "SQLState" ];
			fields[ "nativeErrorCode" ] = [ "nativeErrorCode" ];
			fields[ "additional" ]      = [ "additional" ];

			/* The bound parameter values, e.g. "value='4417'". The most useful
			 * field for reproducing a failure and the only one that can carry
			 * whatever a visitor typed, so an app can turn it off. maskKeys
			 * cannot help here: the values are positional, with no field names
			 * to match against. */
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
	 * Returns the source lines around the line that threw, so the email shows the
	 * failing code without anyone opening an editor. This is the one thing
	 * ColdBox's Whoops page gives that a plain stack trace does not.
	 *
	 * Lucee and BoxLang put a ready-made excerpt on the stack frame as
	 * `codePrintPlain`, but Adobe does not, so the file is read directly instead.
	 * That works the same on every engine. Only the top frame is read, and only
	 * `settings.codeSnippetLines` either side of it.
	 *
	 * Returns empty lines when the setting is 0, the file is gone (a compiled or
	 * archived template), or it cannot be read.
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
	 * Reads the source lines around one file position. Shared by the throw-site
	 * snippet and the application-caller snippet, so both apply the same
	 * file-existence check and readLines() limits.
	 *
	 * Returns the empty snippet shape when the file is gone (a compiled or
	 * archived template) or cannot be read.
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
	 * Reads the lines around a target line. Stops as soon as the range is passed
	 * so a large file is not loaded whole. Each line is capped, because one
	 * minified or generated line could fill the whole email.
	 *
	 * A frame that reports a line past 10,000 is skipped entirely. Such frames
	 * come from generated files, and reaching the line would mean streaming the
	 * whole file on every alert.
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
	 * Walks the `cause` chain and returns each wrapped exception as type,
	 * message, and detail. A framework often catches a low-level error and
	 * rethrows its own, which leaves the real reason only in the chain.
	 *
	 * Stops after five levels so a self-referencing chain cannot loop forever.
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
	 * Returns the origin, the ColdBox event and route, and selected CGI values.
	 * A value the request did not provide shows the settings.emptyValueText
	 * placeholder, so a missing value is visibly missing rather than absent from
	 * the email. Two rows are the exception: `user` only appears when the app
	 * configured a userProvider, and `sessionId` only when
	 * settings.includeScopes.session is true. For those, "N/A" would wrongly
	 * suggest the request lacked a value when the feature is simply off.
	 *
	 * @exception The already-built exception struct, used to find the origin.
	 */
	private struct function buildRequest( struct exception = {} ){
		var info = structNew( "ordered" );

		addValue( info, "origin", buildOrigin( arguments.exception ) );

		// A copy-paste line for reproducing the request, e.g.
		// "GET https://example.com/posts/hello?page=2". Empty outside a web request.
		addValue( info, "url", requestUrl() );

		// Only when the application configured a userProvider closure.
		if ( !isSimpleValue( settings.userProvider ) ) {
			addValue( info, "user", buildUser() );
		}

		try {
			var event = coldbox.getRequestService().getContext();
			addValue( info, "event", event.getCurrentEvent() );
			// Only set on a routed (SES) URL, blank for an index.cfm?event= request.
			addValue( info, "route", event.getCurrentRoutedUrl() );
			// The pattern that matched, e.g. ":slug". Says which route rule ran,
			// which the routed URL on its own does not.
			addValue( info, "routePattern", event.getCurrentRoute() );
			addValue( info, "routeName", event.getCurrentRouteName() );
			addValue( info, "routedModule", event.getCurrentRoutedModule() );
			addValue( info, "routedNamespace", event.getCurrentRoutedNamespace() );
			// How far rendering got before the error.
			addValue( info, "view", event.getCurrentView() );
			addValue( info, "layout", event.getCurrentLayout() );
			// An ajax caller never saw an error page, which explains why a visitor
			// may not have reported anything.
			addValue( info, "isAjax", event.isAjax() ? "yes" : "no" );
		} catch ( any e ) {
			// Keep the promised keys even when the request context is missing
			// or broke partway through. Only keys not already set are filled,
			// so a value read before the failure is not overwritten.
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

		// Not from the request, but they answer "which box" and "was this even a
		// page view". A scheduled task leaves every value above empty, and
		// without these rows nothing in the email explains why.
		addValue( info, "machine", machineName() );
		addValue( info, "context", executionContext() );
		addValue( info, "memory", memoryUsage() );
		// How long the request had been running when it failed. "40 ms in" and
		// "900 ms in" point at very different problems.
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
				// Behind IIS, a load balancer, or Cloudflare, remoteAddr is the
				// proxy. These two carry the real client address and scheme.
				addValue( info, "forwardedFor", cgi.http_x_forwarded_for );
				addValue( info, "forwardedProto", cgi.http_x_forwarded_proto );
				addValue( info, "userAgent", cgi.http_user_agent );
				// Bots and API clients send a distinctive accept header, which
				// helps tell scripted traffic from a real visitor.
				addValue( info, "accept", cgi.http_accept );
				addValue( info, "acceptLanguage", cgi.http_accept_language );
				addValue( info, "https", cgi.https );
				addValue( info, "serverPort", cgi.server_port );
				addValue( info, "serverName", cgi.server_name );
			} catch ( any e ) {
			}
		}

		// Headers the application asked for, e.g. Content-Type, which explains
		// many API failures and is not in the CGI rows above.
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
	 * Returns a description of the logged-in user by calling
	 * settings.userProvider, which the application supplies as a closure and
	 * which receives WireBox. The module stays free of any dependency on a
	 * particular auth library this way.
	 *
	 * Returns an empty string when no provider is set, when it throws, or when it
	 * returns something other than a string. A broken provider must never stop an
	 * alert from being sent.
	 */
	private string function buildUser(){
		try {
			var provider = settings.userProvider;

			// isClosure and isCustomFunction disagree about closures on some
			// engines, so accept either before calling the provider.
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
	 * Returns the session identifier so several alerts from the same visitor can
	 * be tied together, and matched against other logs. Prefers the servlet
	 * session id and falls back to CFID/CFTOKEN.
	 *
	 * Off unless settings.includeScopes.session is true: a live session id in an
	 * email is enough to impersonate that visitor if the mailbox is not private.
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
	 * Returns the host name of the server running the code. Different from the
	 * `serverName` row, which is the host the client asked for — behind a load
	 * balancer several machines answer for one host name, and this says which one
	 * actually failed. Cached because the lookup can touch DNS.
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
	 * Says whether the error came from a page request, a scheduled task, or some
	 * other background thread, and names the Java thread so the alert can be
	 * matched against FusionReactor or an engine log.
	 *
	 * A present cgi.request_method means a real HTTP request. Scheduled tasks and
	 * spawned threads have none, which is what makes the whole Request section
	 * empty for them.
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
	 * Reports JVM heap use at the moment of the failure, e.g.
	 * "312 MB used of 2048 MB max". An OutOfMemoryError rarely names the code
	 * that used the memory, so this row says whether the heap was already under
	 * pressure when the error happened. Reading it costs nothing.
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
	 * Reports how many milliseconds this request had been running when the
	 * error happened, e.g. "412 ms". Lucee and BoxLang expose the request
	 * start on the page context; Adobe does not, so the row is empty there.
	 * Never reads anything that needs admin credentials.
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
	 * Returns one copyable line for reproducing the request:
	 * "GET https://example.com/posts/hello?page=2". The query string passes
	 * through queryStringValue(), so maskQueryString applies. The scheme
	 * prefers the X-Forwarded-Proto header because behind a proxy cgi.https
	 * reports the proxy hop, not what the client used.
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
	 * Returns the CFML engine, Java, ColdBox, and errorAlerts versions for the
	 * email's Runtime section. An error that only happens on one engine or
	 * after an upgrade is invisible without these. Cached because none of them
	 * change while the application is running.
	 *
	 * BoxLang and Lucee both define server.coldfusion for compatibility, so
	 * their own keys are checked first. Keys without a readable value are left
	 * out rather than shown blank.
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
	 * Returns the request headers named in settings.includeHeaders, in that
	 * order. Header names are matched ignoring case because clients vary the
	 * casing. Values pass through sanitizeValue, so maskKeys and the length cap
	 * apply.
	 *
	 * Cookie and Authorization are refused even when listed: both carry
	 * credentials, and email is not a safe place for either.
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
	 * Reads the raw HTTP body and hands it to buildBody(). Split in two so
	 * buildBody() can be tested with a plain struct - getHTTPRequestData() only
	 * works inside a real request.
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
	 * Converts the raw request body to safe text for email. For a JSON or API
	 * request the payload is in the body, not in rc, so without this row a
	 * failing API call shows no input at all.
	 *
	 * Form posts are skipped: their fields are already in the rc table, masked,
	 * and repeating them raw here would print the same secrets unmasked. A JSON
	 * body gets its top-level fields masked through sanitizeScope for the same
	 * reason. Anything else is truncated plain text, and binary content shows
	 * only its size.
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
				try {
					var parsed = deserializeJSON( content );
					if ( isStruct( parsed ) ) {
						return truncate( serializeJSON( sanitizeScope( parsed ) ), settings.requestBodyMaxLength );
					}
				} catch ( any e ) {
				}
			}

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
	 * For a real exception the first stack frame is the throw site, so that wins.
	 * A plain `log.error()` call has no stack frames, so the live CFML call stack
	 * is read instead and the first frame outside this module and LogBox is used.
	 * Returns an empty string when neither is available.
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
	 * Walks the live call stack and returns the first frame that belongs to the
	 * application rather than to the alerting code itself. Frames inside this
	 * module and inside LogBox are skipped, because they are always on the stack
	 * when an alert is built and would hide the real caller.
	 *
	 * Only meaningful while the original call is still running, which is the case
	 * for the appender path. Returns an empty string if the stack is unavailable.
	 */
	private string function callerFrame(){
		try {
			var stack = callStackGet();
			for ( var frame in stack ) {
				if ( !structKeyExists( frame, "template" ) || !frame.template.len() ) {
					continue;
				}
				var template = frame.template.replace( "\", "/", "all" );
				// Skip this module's own frames (paths computed in init, so a
				// non-standard install location still works) and LogBox frames.
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
	 * Trims the application root off a file path so the email shows
	 * `/handlers/Main.cfc` instead of a long absolute path. Returns the path
	 * unchanged when settings.relativePaths is off, and when the file sits
	 * outside the application root.
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
	 * Replaces the value of any query string pair whose name matches
	 * settings.maskKeys. The rc table masks these keys, but the raw query string
	 * would otherwise print a secret from a GET request in full.
	 *
	 * @queryString The raw cgi.query_string value.
	 */
	private string function maskQueryString( required string queryString ){
		if ( !arguments.queryString.len() ) {
			return "";
		}

		var pairs = arguments.queryString.listToArray( "&" );
		var clean = [];

		for ( var pair in pairs ) {
			var name = pair.listFirst( "=" );

			// Compare the decoded name, so an encoded name like "pass%77ord"
			// cannot slip past the mask list.
			var decoded = name;
			try {
				decoded = urlDecode( name );
			} catch ( any e ) {
			}

			// A pair without "=" has no value to hide, so it passes through.
			if ( pair.find( "=" ) && isMasked( decoded ) ) {
				clean.append( "#name#=*** masked ***" );
			} else {
				clean.append( pair );
			}
		}

		return clean.toList( "&" );
	}

	/**
	 * isMasked
	 *
	 * True when a field name appears in settings.maskKeys. The comparison is an
	 * exact match apart from case, so each field an application wants hidden must
	 * be named in the list. Partial matching was deliberately avoided: it hid
	 * fields nobody asked to hide, such as `tokenCount`, which made a value
	 * disappear from a diagnostic email for no reason.
	 *
	 * @key The field name to test.
	 */
	private boolean function isMasked( required string key ){
		return settings.maskKeys.findNoCase( arguments.key ) > 0;
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
	 *
	 * The key must match an entry in settings.maskKeys exactly, ignoring case.
	 * A field is masked only when the application listed it, so a name like
	 * `newPassword` is NOT covered by the entry `password` and has to be added
	 * on its own. The check happens before any conversion so a secret is never
	 * serialized into email.
	 *
	 * @key   The scope key, checked against settings.maskKeys.
	 * @value The value to sanitize, any type.
	 */
	private string function sanitizeValue( required string key, required any value ){
		if ( isMasked( arguments.key ) ) {
			return "*** masked ***";
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
	 * sanitizeDeep
	 *
	 * Returns a copy of a value with every key named in settings.maskKeys
	 * replaced, at any nesting depth. Structs and arrays are walked. Any other
	 * value is returned as it is, so the caller's own length limit still applies.
	 *
	 * This is needed because ColdBox's RestHandler passes getHTTPRequestData()
	 * into extraInfo, which puts the Authorization header into the email.
	 * buildHeaders() cannot help: the hardcoded Cookie and Authorization block
	 * there only covers the Request section, and this value arrives through
	 * extraInfo instead.
	 *
	 * Values are not truncated here. sanitizeValue() clips every value to
	 * rcValueMaxLength, which would cut a stack trace down to nothing, so this
	 * method only masks and lets the caller's stringify() cap the whole result.
	 *
	 * A failure returns a placeholder instead of the original value, so an error
	 * while sanitizing can never print a secret.
	 *
	 * @value The value to sanitize, any type.
	 * @depth The current nesting level. Deep or looping structures stop at 5.
	 */
	private any function sanitizeDeep( required any value, numeric depth = 0 ){
		try {
			if ( arguments.depth > 5 ) {
				return "[nested too deep]";
			}

			if ( isArray( arguments.value ) ) {
				var cleanList = [];
				for ( var item in arguments.value ) {
					cleanList.append( sanitizeDeep( item, arguments.depth + 1 ) );
				}
				return cleanList;
			}

			// isStruct() is true for many object types, so check isObject()
			// first and leave objects alone rather than trying to walk them.
			if ( isObject( arguments.value ) || !isStruct( arguments.value ) ) {
				return arguments.value;
			}

			var clean = structNew( "ordered" );
			for ( var key in arguments.value ) {
				clean[ key ] = isMasked( key ) ? "*** masked ***" : sanitizeDeep(
					arguments.value[ key ],
					arguments.depth + 1
				);
			}
			return clean;
		} catch ( any e ) {
			return "[value could not be sanitized]";
		}
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
