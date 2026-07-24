/**
 * Unit tests for EmailRenderer: Gmail-safe output (no style blocks, classes,
 * or scripts), HTML escaping, the size cap, and the digest variant.
 */
component extends="tests.resources.BaseUnitSpec" {

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
				// encodeForHtml() turns "/" into &##x2f; so assert on the bare name.
				var html = renderer.renderError( newErrorPayload() );
				expect( html ).toInclude( "OrderService.cfc" );
				expect( html ).toInclude( "HarnessBoom" );
			} );

			it( "renders rc and request key/value tables", function(){
				// encodeForHtml() turns "*" into &##x2a; so assert on the bare word.
				var html = renderer.renderError( newErrorPayload() );
				expect( html ).toInclude( "orders.save" );
				expect( html ).toInclude( "masked" );
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

			it( "renders the digest with the burst counts", function(){
				var html = renderer.renderDigest( {
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
					moduleVersion   : "9.9.9"
				} );

				expect( html ).toInclude( "DIGEST" );
				expect( html ).toInclude( "97" );
				expect( html ).toInclude( "Total occurrences" );
				expect( html ).notToInclude( "<style" );
			} );
		} );
	}

	/**
	 * Builds a representative error payload for rendering.
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
				type       : "HarnessBoom",
				message    : "Fixture explosion",
				detail     : "Deliberate test exception",
				tagContext : [
					{ template : "/app/models/OrderService.cfc", line : 42 },
					{ template : "/app/handlers/Orders.cfc", line : 10 }
				]
			},
			request : {
				event  : "orders.save",
				route  : "/orders/save",
				method : "POST"
			},
			rc        : { id : "42", password : "*** masked ***" },
			extraInfo : ""
		};
	}

}
