/**
 * Tests payload fields, exceptions, request data, masking, and missing context.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run(){
		describe( "PayloadBuilder", function(){
			beforeEach( function(){
				settings   = defaultSettings();
				classifier = prepareMock( new errorAlerts.models.FrameClassifier() );
				classifier.$property( propertyName = "settings", mock = settings );
				classifier.$property( propertyName = "coldbox", mock = newControllerStub() );
				builder = prepareMock( new errorAlerts.models.PayloadBuilder() );
				builder.$property( propertyName = "settings", mock = settings );
				builder.$property( propertyName = "coldbox", mock = newControllerStub() );
				builder.$property( propertyName = "frameClassifier", mock = classifier );
			} );

			it( "builds the core payload fields", function(){
				var payload = builder.build( newLogEvent( message = "boom", category = "app.orders" ), "sig-1", 2 );

				expect( payload.type ).toBe( "error" );
				expect( payload.severity ).toBe( "ERROR" );
				expect( payload.category ).toBe( "app.orders" );
				expect( payload.message ).toBe( "boom" );
				expect( payload.appName ).toBe( "StubApp" );
				expect( payload.environment ).toBe( "production" );
				expect( payload.moduleVersion ).toBe( "9.9.9" );
				expect( payload.signature ).toBe( "sig-1" );
				expect( payload.occurrence ).toBe( 2 );
			} );

			it( "extracts the exception block and caps the stack frames", function(){
				settings.stackFrames = 2;
				var payload = builder.build( newLogEvent( extraInfo = newExceptionInfo() ), "sig-1", 1 );

				expect( payload.exception.type ).toBe( "HarnessBoom" );
				expect( payload.exception.message ).toBe( "Fixture explosion" );
				expect( payload.exception.tagContext.len() ).toBe( 2, "frames should cap at settings.stackFrames" );
				expect( payload.exception.tagContext[ 1 ].template ).toBe( "/models/OrderService.cfc", "relativePaths defaults to on" );
				expect( payload.exception.tagContext[ 1 ].line ).toBe( 42 );
			} );

			it( "drops driver frames that are not file paths but keeps the first frame", function(){
				var info        = newExceptionInfo();
				info.tagContext = [
					{ template : "|SQLServer|6.0.0.1282|", line : 1085 },
					{ template : "|SQLServer|6.0.0.1282|", line : 200 },
					{ template : "/app/models/DbService.cfc", line : 12 }
				];
				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );

				expect( payload.exception.tagContext.len() ).toBe( 2, "the throw site stays, the second driver frame goes" );
				expect( payload.exception.tagContext[ 1 ].template ).toInclude( "SQLServer" );
				expect( payload.exception.tagContext[ 2 ].template ).toBe( "/models/DbService.cfc" );
			} );

			it( "returns an empty exception block for non-exception extraInfo", function(){
				var payload = builder.build( newLogEvent( extraInfo = { just : "context" } ), "sig-1", 1 );
				expect( payload.exception ).toBeEmpty();
			} );

			it( "puts non-exception extraInfo in the payload as a bounded string", function(){
				var payload = builder.build( newLogEvent( extraInfo = { just : "context" } ), "sig-1", 1 );
				expect( payload.extraInfo ).toInclude( "context" );
			} );

			it( "masks the Authorization header RestHandler puts in extraInfo", function(){
				/* RestHandler passes getHTTPRequestData() as extraInfo, so every
				 * request header lands in the email. That value never reaches
				 * buildHeaders(), where Cookie and Authorization are blocked. */
				var payload = builder.build(
					newLogEvent( extraInfo = newRestHandlerExtraInfo( "Bearer leak-me-please" ) ),
					"sig-1",
					1
				);

				expect( payload.extraInfo ).toInclude( "*** masked ***" );
				expect( payload.extraInfo ).notToInclude( "leak-me-please" );
			} );

			it( "masks a sensitive key nested several levels down", function(){
				var info = { level1 : { level2 : { password : "nested-secret", keepMe : "visible" } } };

				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );

				expect( payload.extraInfo ).toInclude( "*** masked ***" );
				expect( payload.extraInfo ).notToInclude( "nested-secret" );
				expect( payload.extraInfo ).toInclude( "visible", "a key nobody asked to hide stays readable" );
			} );

			it( "masks sensitive keys inside an array of structs", function(){
				var info = { calls : [ { url : "/v1/orders", apikey : "array-secret" } ] };

				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );

				expect( payload.extraInfo ).notToInclude( "array-secret" );
				expect( payload.extraInfo ).toInclude( "/v1/orders" );
			} );

			it( "does not truncate extraInfo values to rcValueMaxLength", function(){
				/* sanitizeValue() clips to rcValueMaxLength, which would cut a
				 * stack trace down to nothing. Only the caller's 2000-character
				 * cap applies here. */
				var info = { "_stacktrace" : repeatString( "y", 900 ) };

				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );

				expect( payload.extraInfo.len() ).toBeGT(
					settings.rcValueMaxLength * 2,
					"the stack trace must survive masking intact"
				);
			} );

			it( "leaves the exception path untouched when extraInfo is a real exception", function(){
				var payload = builder.build( newLogEvent( extraInfo = newExceptionInfo() ), "sig-1", 1 );

				expect( payload.extraInfo ).toBeEmpty( "an exception fills payload.exception instead" );
				expect( payload.exception.message ).toBe( "Fixture explosion" );
			} );

			it( "sanitizes rc: masks exact key matches, truncates, and serializes complex values", function(){
				var rc = structNew( "ordered" );
				rc[ "id" ]           = "42";
				rc[ "password" ]     = "superSecret!";
				rc[ "PASSWORD" ]     = "upperSecret!";
				rc[ "apiToken" ]     = "abc";
				rc[ "passwordHint" ] = "my hint";
				rc[ "longText" ]     = repeatString( "x", 500 );
				rc[ "filters" ]      = { status : "active" };
				rc[ "payload" ]      = toBinary( toBase64( "binary content" ) );
				builder.$property( propertyName = "coldbox", mock = newControllerStub( rc ) );

				var result = builder.build( newLogEvent(), "sig-1", 1 ).rc;

				expect( result.id ).toBe( "42" );
				expect( result[ "password" ] ).toBe( "*** masked ***" );
				expect( result[ "PASSWORD" ] ).toBe( "*** masked ***", "matching ignores case" );
				expect( result.apiToken ).toBe( "abc", "exact matching must not hide a key that merely contains 'token'" );
				expect( result.passwordHint ).toBe( "my hint", "a near-miss key must not be masked" );
				expect( result.longText.len() ).toBeLTE( settings.rcValueMaxLength + 1, "truncated plus ellipsis" );
				expect( result.filters ).toInclude( "active" );
				expect( result.payload ).toInclude( "binary" );
			} );

			it( "captures the ColdBox event, routing detail, and the CGI subset", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );

				expect( payload.request.event ).toBe( "orders.save" );
				expect( payload.request.route ).toBe( "/orders/save" );
				expect( payload.request.routePattern ).toBe( "orders/:action/" );
				expect( payload.request.isAjax ).toBe( "no" );
				expect( payload.request ).toHaveKey( "origin" );
				expect( payload.request ).toHaveKey( "method" );
				expect( payload.request ).toHaveKey( "remoteAddr" );
				expect( payload.request ).toHaveKey( "userAgent" );
				expect( payload.request ).toHaveKey( "forwardedFor" );
			} );

			it( "returns placeholder request rows and an empty rc when there is no request context", function(){
				var broken = createStub();
				broken.$( "getSetting", "" );
				broken.$(
					method         = "getRequestService",
					throwException = true,
					throwType      = "NoContext",
					throwMessage   = "no request here"
				);
				builder.$property( propertyName = "coldbox", mock = broken );
				settings.includeScopes.cgi = false;

				var payload = builder.build( newLogEvent(), "sig-1", 1 );

				expect( payload.rc ).toBeEmpty();
				expect( payload.request.event ).toBe( settings.emptyValueText );
				expect( payload.request.route ).toBe( settings.emptyValueText );
				expect( payload.request ).toHaveKey( "routePattern", "every routing key survives a broken context" );
				expect( payload.request ).toHaveKey( "view" );
				expect( payload.request ).toHaveKey( "origin" );
				expect( payload.request ).toHaveKey( "context" );
				expect( payload.request.machine ).notToBe( settings.emptyValueText );
				expect( payload.request ).notToHaveKey( "user", "no userProvider configured, so no user row" );
				expect( payload.request ).notToHaveKey( "sessionId", "session scope is off by default" );
				expect( payload.request ).notToHaveKey( "method", "cgi rows are off" );
			} );

			it( "reports the origin from the exception's top stack frame", function(){
				var payload = builder.build( newLogEvent( extraInfo = newExceptionInfo() ), "sig-1", 1 );
				expect( payload.request.origin ).toBe( "/models/OrderService.cfc:42" );
			} );

			it( "reports the origin from the live call stack when there is no exception", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.request.origin ).notToBe( settings.emptyValueText );
				expect( payload.request.origin ).toMatch( ".+:\d+" );
				expect( payload.request.origin ).notToInclude( "PayloadBuilder.cfc", "the module must skip its own frames" );
			} );

			it( "keeps the full path when relativePaths is off", function(){
				settings.relativePaths = false;
				var payload = builder.build( newLogEvent( extraInfo = newExceptionInfo() ), "sig-1", 1 );

				expect( payload.exception.tagContext[ 1 ].template ).toBe( "/app/models/OrderService.cfc" );
				expect( payload.request.origin ).toBe( "/app/models/OrderService.cfc:42" );
			} );

			it( "pins the first application frame that falls past the display cap", function(){
				var ex = builder.build( newLogEvent( extraInfo = newDeepExceptionInfo() ), "sig-1", 1 ).exception;

				expect( ex.totalFrames ).toBe( 16 );
				expect( ex.tagContext.len() ).toBe( 11, "ten displayable frames plus the pinned caller" );
				expect( ex.tagContext[ 11 ].template ).toBe( "/views/posts/_card.cfm" );
				expect( ex.tagContext[ 11 ].line ).toBe( 14 );
				expect( ex.tagContext[ 11 ].application ).toBeTrue();
				expect( ex.tagContext[ 11 ].index ).toBe( 13, "the pinned frame keeps its raw stack position" );
				expect( ex.tagContext[ 1 ].application ).toBeFalse( "dependency code under /modules/ is not application code" );
				expect( ex.omittedFrames ).toBe( 5, "sixteen raw frames minus eleven shown" );
				expect( ex.actionableFrame.index ).toBe( 13 );
			} );

			it( "adds no pinned frame and no counts noise when no application frame exists", function(){
				var info        = newExceptionInfo();
				info.tagContext = [
					{ template : "/elsewhere/lib/Thing.cfc", line : 5 },
					{ template : "/coldbox/system/EventHandler.cfc", line : 99 }
				];
				var ex = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 ).exception;

				expect( ex.actionableFrame ).toBeEmpty();
				expect( ex.tagContext.len() ).toBe( 2 );
				expect( ex.omittedFrames ).toBe( 0 );
				expect( ex.callerSnippet.lines ).toBeEmpty();
			} );

			it( "keeps the function name when the engine supplies one", function(){
				var info = newExceptionInfo();
				info.tagContext[ 1 ][ "function" ] = "getCategories";
				info.tagContext[ 2 ][ "id" ]       = "??";
				var ex = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 ).exception;

				expect( ex.tagContext[ 1 ].fn ).toBe( "getCategories" );
				expect( ex.tagContext[ 2 ].fn ).toBe( "", "Lucee's '??' placeholder is dropped" );
			} );

			it( "reads a second snippet at the application caller", function(){
				settings.codeSnippetLines = 2;
				// Point the classifier at the real harness root and treat /tests/
				// as application code, so the readable fixture file qualifies.
				settings.applicationFramePrefixes = [ "/tests/" ];
				var harnessRootStub = newControllerStub();
				harnessRootStub.$( "getAppRootPath", expandPath( "/" ) );
				classifier.$property( propertyName = "coldbox", mock = harnessRootStub );

				var info = newDeepExceptionInfo(
					callerTemplate = expandPath( "/tests/resources/fixtures/snippet.cfm" ),
					callerLine     = 5
				);
				var ex = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 ).exception;

				expect( ex.callerSnippet.line ).toBe( 5 );
				expect( ex.callerSnippet.lines.len() ).toBe( 5, "two lines either side of line 5" );
				expect( ex.callerSnippet.lines[ 3 ].isError ).toBeTrue();
				expect( ex.callerSnippet.lines[ 3 ].text ).toBe( "fixture line 5" );
			} );

			it( "leaves the caller snippet empty when the caller file cannot be read", function(){
				var ex = builder.build( newLogEvent( extraInfo = newDeepExceptionInfo() ), "sig-1", 1 ).exception;

				expect( ex.callerSnippet.lines ).toBeEmpty( "the fixture path does not exist on disk" );
				expect( ex.tagContext.len() ).toBeGT( 0, "an unreadable caller file must not suppress the alert" );
			} );

			it( "reports database detail and caps the SQL", function(){
				var info            = newExceptionInfo();
				info.sql            = repeatString( "S", 2500 );
				info.datasource     = "myDsn";
				info.sqlState       = "42S02";
				info.nativeErrorCode = "208";
				info.where          = "value='4417'";
				var db = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 ).exception.database;

				expect( db.sql.len() ).toBeLTE( 2001, "2000 characters plus the ellipsis" );
				expect( db.datasource ).toBe( "myDsn" );
				expect( db.sqlState ).toBe( "42S02" );
				expect( db ).toHaveKey( "params" );
				expect( db.params ).toInclude( "4417" );
			} );

			it( "leaves query params out when includeQueryParams is off", function(){
				settings.includeQueryParams = false;
				var info   = newExceptionInfo();
				info.sql   = "SELECT 1";
				info.where = "value='4417'";
				var db = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 ).exception.database;

				expect( db ).notToHaveKey( "params" );
			} );

			it( "falls back to Adobe's errNumber spelling for the error code", function(){
				var info       = newExceptionInfo();
				info.errNumber = 1234;
				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );
				expect( payload.exception.errorCode ).toBe( "1234" );
			} );

			it( "firstOf picks the first key with content and returns '' for none", function(){
				makePublic( builder, "firstOf" );
				expect( builder.firstOf( { a : "", b : " ", c : "x" }, [ "a", "b", "c" ] ) ).toBe( "x" );
				expect( builder.firstOf( { a : "" }, [ "a", "missing" ] ) ).toBe( "" );
			} );

			it( "walks the cause chain and stops at five levels", function(){
				var info    = newExceptionInfo();
				var current = info;
				for ( var i = 1; i <= 7; i++ ) {
					current.cause = { type : "Level#i#", message : "cause #i#" };
					current       = current.cause;
				}
				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );

				expect( payload.exception.causes.len() ).toBe( 5 );
				expect( payload.exception.causes[ 1 ].type ).toBe( "Level1" );
			} );

			it( "does not loop on a self-referencing cause chain", function(){
				var info   = newExceptionInfo();
				info.cause = info;
				var payload = builder.build( newLogEvent( extraInfo = info ), "sig-1", 1 );
				expect( payload.exception.causes.len() ).toBeLTE( 5 );
			} );

			it( "reads the source snippet around the failing line", function(){
				settings.codeSnippetLines = 2;
				var payload = builder.build(
					newLogEvent(
						extraInfo = newExceptionInfo(
							template = expandPath( "/tests/resources/fixtures/snippet.cfm" ),
							line     = 5
						)
					),
					"sig-1",
					1
				);
				var snippet = payload.exception.snippet;

				expect( snippet.line ).toBe( 5 );
				expect( snippet.lines.len() ).toBe( 5, "two lines either side of line 5" );
				expect( snippet.lines[ 1 ].number ).toBe( 3 );
				expect( snippet.lines[ 3 ].number ).toBe( 5 );
				expect( snippet.lines[ 3 ].isError ).toBeTrue();
				expect( snippet.lines[ 3 ].text ).toBe( "fixture line 5" );
				expect( snippet.lines[ 1 ].isError ).toBeFalse();
				expect( snippet.lines[ 5 ].number ).toBe( 7 );
			} );

			it( "returns no snippet when codeSnippetLines is 0 or the file is missing", function(){
				settings.codeSnippetLines = 0;
				var payload = builder.build( newLogEvent( extraInfo = newExceptionInfo() ), "sig-1", 1 );
				expect( payload.exception.snippet.lines ).toBeEmpty();

				settings.codeSnippetLines = 5;
				var missing = builder.build(
					newLogEvent( extraInfo = newExceptionInfo( template = "/nope/gone.cfm", line = 5 ) ),
					"sig-1",
					1
				);
				expect( missing.exception.snippet.lines ).toBeEmpty();
			} );

			it( "reports the user from the userProvider closure", function(){
				settings.userProvider = function( wirebox ){
					return "user-42";
				};
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.request.user ).toBe( "user-42" );
			} );

			it( "shows the placeholder when the userProvider throws or returns a non-string", function(){
				settings.userProvider = function( wirebox ){
					throw( type = "Broken", message = "provider blew up" );
				};
				expect( builder.build( newLogEvent(), "sig-1", 1 ).request.user ).toBe( settings.emptyValueText );

				settings.userProvider = function( wirebox ){
					return { name : "not a string" };
				};
				expect( builder.build( newLogEvent(), "sig-1", 1 ).request.user ).toBe( settings.emptyValueText );
			} );

			it( "omits the user row when no userProvider is configured", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.request ).notToHaveKey( "user" );
			} );

			it( "omits the sessionId row unless includeScopes.session is on", function(){
				expect( builder.build( newLogEvent(), "sig-1", 1 ).request ).notToHaveKey( "sessionId" );

				settings.includeScopes.session = true;
				expect( builder.build( newLogEvent(), "sig-1", 1 ).request ).toHaveKey( "sessionId" );
			} );

			it( "reports the machine, execution context, and heap use", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.request.machine.len() ).toBeGT( 0 );
				expect( payload.request.context ).toInclude( "web request" );
				expect( payload.request.memory ).toMatch( "\d+ MB used of \d+ MB max" );
			} );

			it( "builds a copyable request URL from the live request", function(){
				// The spec itself runs inside a web request, so the CGI scope is real.
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.request ).toHaveKey( "url" );
				expect( payload.request.url ).toMatch( "^[A-Z]+ https?://.+" );
			} );

			it( "masks secrets in the request URL's query string", function(){
				makePublic( builder, "requestUrl" );
				// The URL row must reuse queryStringValue(), which applies maskKeys.
				builder.$( "queryStringValue", "token=*** masked ***" );

				// Not named "url": that would collide with the CFML url scope.
				var urlLine = builder.requestUrl();
				expect( urlLine ).toInclude( "masked" );
				expect( urlLine ).toInclude( "?", "the stubbed query string is appended" );
			} );

			it( "reports the runtime versions and caches them", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );

				expect( payload ).toHaveKey( "runtime" );
				expect( payload.runtime ).toHaveKey( "engine" );
				expect( payload.runtime ).toHaveKey( "java" );
				expect( payload.runtime.errorAlerts ).toBe( "9.9.9", "the module version comes from the registry" );

				var again = builder.build( newLogEvent(), "sig-1", 1 );
				expect( again.runtime ).toBe( payload.runtime, "the struct is cached, not rebuilt" );
			} );

			it( "reports the elapsed request time when the engine exposes it", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				// Lucee and BoxLang expose the request start; Adobe shows the
				// placeholder. Both are acceptable, crashing is not.
				expect( payload.request ).toHaveKey( "elapsed" );
				expect( payload.request.elapsed == settings.emptyValueText || payload.request.elapsed.reFind( "^\d+ ms$" ) ).toBeTrue();
			} );

			it( "masks query string values for exact key matches only", function(){
				makePublic( builder, "maskQueryString" );
				var masked = builder.maskQueryString( "id=1&token=abc&passwordHint=x&PASSWORD=y&debug" );
				expect( masked ).toBe( "id=1&token=*** masked ***&passwordHint=x&PASSWORD=*** masked ***&debug" );
				expect( builder.maskQueryString( "" ) ).toBe( "" );
			} );

			it( "masks a url-encoded query string name", function(){
				makePublic( builder, "maskQueryString" );
				expect( builder.maskQueryString( "pass%77ord=abc" ) ).toBe( "pass%77ord=*** masked ***" );
			} );

			it( "includes allowlisted headers and refuses credential headers", function(){
				makePublic( builder, "buildHeaders" );
				settings.includeHeaders = [ "Content-Type", "Authorization", "Cookie", "X-Request-Id" ];
				var headers = builder.buildHeaders( {
					"content-type"  : "application/json",
					"authorization" : "Bearer shh",
					"cookie"        : "cfid=1",
					"X-Request-Id"  : "req-9"
				} );

				expect( headers[ "Content-Type" ] ).toBe( "application/json" );
				expect( headers[ "X-Request-Id" ] ).toBe( "req-9" );
				expect( headers ).notToHaveKey( "Authorization" );
				expect( headers ).notToHaveKey( "Cookie" );
			} );

			it( "masks and caps a JSON request body", function(){
				makePublic( builder, "buildBody" );
				var body = builder.buildBody( {
					headers : { "Content-Type" : "application/json" },
					content : serializeJSON( { orderId : 7, apiKey : "shh" } )
				} );

				expect( body ).toInclude( "7" );
				expect( body ).notToInclude( "shh", "a JSON field named in maskKeys must be masked" );
				expect( body ).toInclude( "masked" );
			} );

			it( "skips form bodies and reports binary bodies by size", function(){
				makePublic( builder, "buildBody" );
				expect(
					builder.buildBody( {
						headers : { "Content-Type" : "application/x-www-form-urlencoded" },
						content : "password=shh"
					} )
				).toBe( "", "form fields are already in rc, masked" );

				var binary = builder.buildBody( {
					headers : {},
					content : toBinary( toBase64( "binary content" ) )
				} );
				expect( binary ).toInclude( "binary" );
			} );

			it( "truncates an oversized plain-text body and stays off by default", function(){
				makePublic( builder, "buildBody" );
				settings.requestBodyMaxLength = 100;
				var body = builder.buildBody( { headers : {}, content : repeatString( "b", 500 ) } );
				expect( body.len() ).toBeLTE( 101, "100 characters plus the ellipsis" );

				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.requestBody ).toBe( "", "includeRequestBody defaults to false" );
			} );

			it( "maps a digest seed onto the digest payload", function(){
				var payload = builder.buildDigest( {
					signature       : "sig-9",
					message         : "boom",
					category        : "app.orders",
					severity        : 1,
					totalCount      : 100,
					sentCount       : 3,
					suppressedCount : 97,
					firstSeen       : now(),
					lastSeen        : now(),
					windowSeconds   : 600
				} );

				expect( payload.type ).toBe( "digest" );
				expect( payload.severity ).toBe( "ERROR" );
				expect( payload.suppressedCount ).toBe( 97 );
				expect( payload.appName ).toBe( "StubApp" );
				expect( payload ).toHaveKey( "machine", "the digest names the server that flushed it" );
			} );
		} );
	}

	/**
	 * newControllerStub
	 *
	 * Builds a controller stub with settings and a request collection. The event
	 * stub answers every context method PayloadBuilder calls, so a missing stub
	 * method cannot silently drop the whole routing block into its catch.
	 *
	 * @rc The request collection the stubbed context returns.
	 */
	private any function newControllerStub( struct rc = {} ){
		var eventStub = createStub();
		eventStub.$( "getCurrentEvent", "orders.save" );
		eventStub.$( "getCurrentRoutedUrl", "/orders/save" );
		eventStub.$( "getCurrentRoute", "orders/:action/" );
		eventStub.$( "getCurrentRouteName", "orderSave" );
		eventStub.$( "getCurrentRoutedModule", "" );
		eventStub.$( "getCurrentRoutedNamespace", "" );
		eventStub.$( "getCurrentView", "orders/save" );
		eventStub.$( "getCurrentLayout", "Main.cfm" );
		eventStub.$( "isAjax", false );
		eventStub.$( "getCollection", arguments.rc );

		var requestServiceStub = createStub();
		requestServiceStub.$( "getContext", eventStub );

		var controllerStub = createStub();
		controllerStub.$( "getRequestService", requestServiceStub );
		controllerStub.$( "getWireBox", createStub() );
		controllerStub.$( "getAppRootPath", "/app/" );
		controllerStub.$( "getSetting" ).$callback( function( required name ){
			switch ( arguments.name ) {
				case "appName":
					return "StubApp";
				case "environment":
					return "production";
				case "modules":
					return { errorAlerts : { version : "9.9.9" } };
				default:
					return "";
			}
		} );

		return controllerStub;
	}

}
