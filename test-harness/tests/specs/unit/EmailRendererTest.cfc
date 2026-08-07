/**
 * Tests inline HTML, escaping, length limits, and digest rendering.
 */
component extends="tests.resources.BaseUnitSpec" {

	/**
	 * run
	 *
	 * Defines EmailRenderer unit tests.
	 */
	function run(){
		describe( "EmailRenderer", function(){
			beforeEach( function(){
				settings = defaultSettings();
				renderer = prepareMock( new errorAlerts.models.EmailRenderer() );
				renderer.$property( propertyName = "settings", mock = settings );
			} );

			it( "emits only inline styles: no style blocks, classes, or scripts", function(){
				var html = renderer.renderError( newErrorPayload() );
				expect( html ).notToInclude( "<style" );
				expect( html ).notToInclude( "class=" );
				expect( html.lcase() ).notToInclude( "<script" );
			} );

			it( "HTML-encodes every dynamic value", function(){
				var payload     = newErrorPayload();
				payload.message = "boom <script>alert(1)</script>";
				payload.rc      = { note : "<img src=x onerror=alert(1)>" };

				var html = renderer.renderError( payload );
				expect( html.lcase() ).notToInclude( "<script>" );
				expect( html ).toInclude( "&lt;script&gt;" );
				expect( html ).notToInclude( "<img" );
			} );

			it( "renders the exception stack frames", function(){
				// Assert only the file name because encodeForHtml() escapes "/".
				var html = renderer.renderError( newErrorPayload() );
				expect( html ).toInclude( "OrderService.cfc" );
				expect( html ).toInclude( "HarnessBoom" );
			} );

			it( "renders an older payload missing the newer exception keys", function(){
				// Version 2.0 payloads do not have the newer optional keys.
				var payload       = newErrorPayload();
				payload.exception = {
					type       : "HarnessBoom",
					message    : "Fixture explosion",
					detail     : "Deliberate test exception",
					tagContext : [ { template : "/app/models/OrderService.cfc", line : 42 } ]
				};
				payload.delete( "requestBody" );

				var html = renderer.renderError( payload );
				expect( html ).toInclude( "HarnessBoom" );
				expect( html ).toInclude( "OrderService.cfc" );
			} );

			it( "renders the source snippet with the failing line highlighted", function(){
				var payload               = newErrorPayload();
				payload.exception.snippet = {
					template : "/app/x.cfm",
					line     : 5,
					lines    : [
						{ number : 4, text : "fixture line 4", isError : false },
						{ number : 5, text : "fixture line 5", isError : true }
					]
				};

				var html = renderer.renderError( payload );
				expect( html ).toInclude( "Source" );
				expect( html ).toInclude( "fixture line 5" );
				expect( html ).toInclude( "fee2e2", "the failing line gets the red background" );
			} );

			it( "labels the two snippets as throw site and application caller", function(){
				var payload               = newErrorPayload();
				payload.exception.snippet = {
					template : "/modules/qb/BaseGrammar.cfc",
					line     : 128,
					lines    : [ { number : 128, text : "return sql;", isError : true } ]
				};
				payload.exception.callerSnippet = {
					template : "/views/posts/_card.cfm",
					line     : 14,
					lines    : [ { number : 14, text : "local.cats = args.post.getCategories();", isError : true } ]
				};

				var html = renderer.renderError( payload );
				expect( html ).toInclude( "Throw site" );
				expect( html ).toInclude( "Application caller" );
				expect( html ).notToInclude( "Source - ", "the plain label is replaced when both snippets exist" );
			} );

			it( "marks omitted frames and highlights the pinned application caller", function(){
				var payload                   = newErrorPayload();
				payload.exception.totalFrames = 16;
				payload.exception.tagContext  = [
					{ template : "/modules/qb/BaseGrammar.cfc", line : 128, index : 1, application : false, fn : "" },
					{ template : "/modules/quick/BaseEntity.cfc", line : 2509, index : 3, application : false, fn : "get" },
					{ template : "/views/posts/_card.cfm", line : 14, index : 13, application : true, fn : "" }
				];

				var html = renderer.renderError( payload );
				expect( html ).toInclude( "1 frame omitted", "the skipped driver frame between raw positions 1 and 3" );
				expect( html ).toInclude( "9 frames omitted", "the gap before the pinned caller" );
				expect( html ).toInclude( "3 more frames not shown" );
				expect( html ).toInclude( "dbeafe", "the application frame gets the blue tint" );
				expect( html ).toInclude( "_card.cfm" );
			} );

			it( "renders database detail and suppresses a code that repeats sqlState", function(){
				var payload                 = newErrorPayload();
				payload.exception.errorCode = "42S02";
				payload.exception.database  = {
					sql        : "SELECT boom",
					datasource : "myDsn",
					sqlState   : "42S02"
				};

				var html = renderer.renderError( payload );
				expect( html ).toInclude( "Database" );
				expect( html ).toInclude( "SELECT boom" );
				expect( html ).toInclude( "myDsn" );
				expect( html ).notToInclude( "code 42S02", "the code would just repeat the sqlState row" );

				payload.exception.errorCode = "1234";
				expect( renderer.renderError( payload ) ).toInclude( "code 1234" );
			} );

			it( "renders the cause chain and extended info", function(){
				var payload                    = newErrorPayload();
				payload.exception.causes       = [ { type : "SQLGrammar", message : "bad column", detail : "" } ];
				payload.exception.extendedInfo = "field errors here";

				var html = renderer.renderError( payload );
				expect( html ).toInclude( "Caused by" );
				expect( html ).toInclude( "SQLGrammar" );
				expect( html ).toInclude( "Extended info" );
			} );

			it( "renders the Runtime section only when the payload carries it", function(){
				var payload = newErrorPayload();
				expect( renderer.renderError( payload ) ).notToInclude( "Runtime", "an older payload has no runtime key" );

				payload.runtime = {
					engine      : "Lucee 5.4.8.2",
					java        : "11.0.32",
					coldbox     : "7.2.0",
					errorAlerts : "9.9.9"
				};
				var html = renderer.renderError( payload );
				expect( html ).toInclude( "Runtime" );
				expect( html ).toInclude( "5.4.8.2" );
			} );

			it( "renders the request body section only when present", function(){
				var payload         = newErrorPayload();
				payload.requestBody = "{""orderId"":7}";
				expect( renderer.renderError( payload ) ).toInclude( "Request body" );

				payload.requestBody = "";
				expect( renderer.renderError( payload ) ).notToInclude( "Request body" );
			} );

			it( "renders rc and request key/value tables", function(){
				// Assert only the word because encodeForHtml() escapes "*".
				var html = renderer.renderError( newErrorPayload() );
				expect( html ).toInclude( "orders.save" );
				expect( html ).toInclude( "masked" );
			} );

			it( "words the throttle window correctly under and over a minute", function(){
				var payload           = newErrorPayload();
				payload.windowSeconds = 30;
				expect( renderer.renderError( payload ) ).toInclude( "30-second window" );

				payload.windowSeconds = 600;
				expect( renderer.renderError( payload ) ).toInclude( "10-minute window" );

				settings.throttle.windowSeconds = 45;
				expect( renderer.renderError( payload ) ).toInclude( "45 seconds", "the footer sentence uses the noun form" );
			} );

			it( "stamps timestamps with a timezone label", function(){
				var html = renderer.renderError( newErrorPayload() );
				expect( html ).toMatch( "\d{2}:\d{2}:\d{2} \S" );
			} );

			it( "respects the size cap and marks the truncation", function(){
				settings.maxBodyBytes = 5000;

				var payload = newErrorPayload();
				for ( var i = 1; i <= 100; i++ ) {
					payload.rc[ "key#i#" ] = repeatString( "v", 200 );
				}

				var html = renderer.renderError( payload );
				expect( html.len() ).toBeLTE( settings.maxBodyBytes );
				expect( html.lcase() ).toInclude( "truncated" );
			} );

			it( "renders the digest with the burst counts and machine", function(){
				var html = renderer.renderDigest( newDigestPayload() );

				expect( html ).toInclude( "DIGEST" );
				expect( html ).toInclude( "97" );
				expect( html ).toInclude( "Total occurrences" );
				expect( html ).toInclude( "APOLLO", "the digest names the server that flushed it" );
				expect( html ).notToInclude( "<style" );
			} );

			it( "lists the digest's distinct routes and clients with overflow wording", function(){
				var digest      = newDigestPayload();
				digest.samples  = {
					route  : [ "blog/one/", "blog/two/", "blog/three/" ],
					client : [ "152.163.122.15" ]
				};
				digest.overflow = { route : true, client : false };

				var html = renderer.renderDigest( digest );
				expect( html ).toInclude( "Routes" );
				expect( html ).toInclude( "at least 3 distinct", "the overflow flag changes the wording" );
				expect( html ).toInclude( "Client IPs" );
				expect( html ).toInclude( "1 distinct" );
				expect( html ).toInclude( "152.163.122.15" );
			} );

			it( "renders a digest payload without samples, as older module versions built it", function(){
				var html = renderer.renderDigest( newDigestPayload() );
				expect( html ).toInclude( "DIGEST" );
				expect( html ).notToInclude( "Routes" );
				expect( html ).notToInclude( "Client IPs" );
			} );

			it( "labels the digest window in seconds or minutes", function(){
				var digest           = newDigestPayload();
				digest.windowSeconds = 1;
				var html = renderer.renderDigest( digest );
				expect( html ).toInclude( "1 second" );
				expect( html ).notToInclude( "1 seconds" );

				digest.windowSeconds = 600;
				expect( renderer.renderDigest( digest ) ).toInclude( "10 minutes" );
			} );
		} );
	}

	/**
	 * newErrorPayload
	 *
	 * Builds an error payload with every rendered section, in the shape
	 * PayloadBuilder.build() produces today.
	 */
	private struct function newErrorPayload(){
		return {
			type          : "error",
			severity      : "ERROR",
			category      : "app.orders",
			message       : "Order save failed",
			timestamp     : now(),
			appName       : "StubApp",
			environment   : "production",
			moduleVersion : "9.9.9",
			signature     : "sig-abc",
			occurrence    : 1,
			maxPerWindow  : 3,
			windowSeconds : 600,
			exception     : {
				type         : "HarnessBoom",
				message      : "Fixture explosion",
				detail       : "Deliberate test exception",
				errorCode    : "",
				extendedInfo : "",
				database     : {},
				causes       : [],
				snippet      : { template : "", line : 0, lines : [] },
				tagContext   : [
					{ template : "/app/models/OrderService.cfc", line : 42 },
					{ template : "/app/handlers/Orders.cfc", line : 10 }
				]
			},
			request : {
				origin  : "/app/models/OrderService.cfc:42",
				event   : "orders.save",
				route   : "/orders/save",
				machine : "APOLLO",
				context : "web request (http-1)",
				memory  : "312 MB used of 2048 MB max",
				method  : "POST"
			},
			rc          : { id : "42", password : "*** masked ***" },
			requestBody : "",
			extraInfo   : ""
		};
	}

	/**
	 * newDigestPayload
	 *
	 * Builds a digest payload in the shape PayloadBuilder.buildDigest() produces.
	 */
	private struct function newDigestPayload(){
		return {
			type            : "digest",
			severity        : "ERROR",
			signature       : "sig-9",
			category        : "app.orders",
			message         : "boom",
			totalCount      : 100,
			sentCount       : 3,
			suppressedCount : 97,
			firstSeen       : now(),
			lastSeen        : now(),
			windowSeconds   : 600,
			appName         : "StubApp",
			environment     : "production",
			machine         : "APOLLO",
			moduleVersion   : "9.9.9"
		};
	}

}
