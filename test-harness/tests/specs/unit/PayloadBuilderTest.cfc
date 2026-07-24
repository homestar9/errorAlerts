/**
 * Tests payload fields, exceptions, request data, masking, and missing context.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run(){
		describe( "PayloadBuilder", function(){
			beforeEach( function(){
				settings = defaultSettings();
				builder  = prepareMock( new errorAlerts.models.PayloadBuilder() );
				builder.$property( propertyName = "settings", mock = settings );
				builder.$property( propertyName = "coldbox", mock = newControllerStub() );
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
				expect( payload.exception.tagContext[ 1 ].template ).toBe( "/app/models/OrderService.cfc" );
				expect( payload.exception.tagContext[ 1 ].line ).toBe( 42 );
			} );

			it( "returns an empty exception block for non-exception extraInfo", function(){
				var payload = builder.build( newLogEvent( extraInfo = { just : "context" } ), "sig-1", 1 );
				expect( payload.exception ).toBeEmpty();
			} );

			it( "puts non-exception extraInfo in the payload as a bounded string", function(){
				var payload = builder.build( newLogEvent( extraInfo = { just : "context" } ), "sig-1", 1 );
				expect( payload.extraInfo ).toInclude( "context" );
			} );

			it( "sanitizes rc: masks secrets, truncates, and serializes complex values", function(){
				var rc = structNew( "ordered" );
				rc[ "id" ]       = "42";
				rc[ "password" ] = "superSecret!";
				rc[ "apiToken" ] = "abc";
				rc[ "longText" ] = repeatString( "x", 500 );
				rc[ "filters" ]  = { status : "active" };
				rc[ "payload" ]  = toBinary( toBase64( "binary content" ) );
				builder.$property( propertyName = "coldbox", mock = newControllerStub( rc ) );

				var result = builder.build( newLogEvent(), "sig-1", 1 ).rc;

				expect( result.id ).toBe( "42" );
				expect( result.password ).toBe( "*** masked ***" );
				expect( result.apiToken ).toBe( "*** masked ***", "token substring should mask" );
				expect( result.longText.len() ).toBeLTE( settings.rcValueMaxLength + 1, "truncated plus ellipsis" );
				expect( result.filters ).toInclude( "active" );
				expect( result.payload ).toInclude( "binary" );
			} );

			it( "captures the ColdBox event and the CGI subset", function(){
				var payload = builder.build( newLogEvent(), "sig-1", 1 );
				expect( payload.request.event ).toBe( "orders.save" );
				expect( payload.request.route ).toBe( "/orders/save" );
				expect( payload.request ).toHaveKey( "method" );
				expect( payload.request ).toHaveKey( "remoteAddr" );
				expect( payload.request ).toHaveKey( "userAgent" );
			} );

			it( "produces empty request and rc blocks when there is no request context", function(){
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
				expect( payload.request ).toBeEmpty();
				expect( payload.rc ).toBeEmpty();
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
			} );
		} );
	}

	/**
	 * newControllerStub
	 *
	 * Builds a controller stub with settings and a request collection.
	 *
	 * @rc The request collection the stubbed context returns.
	 */
	private any function newControllerStub( struct rc = {} ){
		var eventStub = createStub();
		eventStub.$( "getCurrentEvent", "orders.save" );
		eventStub.$( "getCurrentRoutedUrl", "/orders/save" );
		eventStub.$( "getCollection", arguments.rc );

		var requestServiceStub = createStub();
		requestServiceStub.$( "getContext", eventStub );

		var controllerStub = createStub();
		controllerStub.$( "getRequestService", requestServiceStub );
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
