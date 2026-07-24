/**
 * Tests signature stability, input changes, and ID normalization.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run(){
		describe( "SignatureService", function(){
			beforeEach( function(){
				service = prepareMock( new errorAlerts.models.SignatureService() );
				service.$property( propertyName = "settings", mock = defaultSettings() );
			} );

			it( "returns the same hash for identical events", function(){
				var a = service.compute( newLogEvent( message = "boom", category = "app.orders" ) );
				var b = service.compute( newLogEvent( message = "boom", category = "app.orders" ) );
				expect( a ).toBe( b );
				expect( a.len() ).toBe( 32 );
			} );

			it( "changes the hash when the category changes", function(){
				var a = service.compute( newLogEvent( message = "boom", category = "app.orders" ) );
				var b = service.compute( newLogEvent( message = "boom", category = "app.users" ) );
				expect( a ).notToBe( b );
			} );

			it( "changes the hash when the message changes", function(){
				var a = service.compute( newLogEvent( message = "boom one" ) );
				var b = service.compute( newLogEvent( message = "boom two" ) );
				expect( a ).notToBe( b );
			} );

			it( "changes the hash when the top stack frame changes", function(){
				var a = service.compute( newLogEvent( extraInfo = newExceptionInfo( template = "/a.cfc", line = 1 ) ) );
				var b = service.compute( newLogEvent( extraInfo = newExceptionInfo( template = "/b.cfc", line = 1 ) ) );
				expect( a ).notToBe( b );
			} );

			it( "only hashes the first 200 characters of the message", function(){
				var common = repeatString( "x", 200 );
				var a      = service.compute( newLogEvent( message = common & "AAA" ) );
				var b      = service.compute( newLogEvent( message = common & "BBB" ) );
				expect( a ).toBe( b );
			} );

			it( "folds messages that differ only by numbers into one signature", function(){
				var a = service.compute( newLogEvent( message = "Order 123 failed" ) );
				var b = service.compute( newLogEvent( message = "Order 98765 failed" ) );
				expect( a ).toBe( b );
			} );

			it( "folds messages that differ only by UUIDs into one signature", function(){
				var a = service.compute( newLogEvent( message = "Lookup #createUUID()# failed" ) );
				var b = service.compute( newLogEvent( message = "Lookup #createUUID()# failed" ) );
				expect( a ).toBe( b );
			} );

			it( "keeps id-bearing messages apart when normalization is off", function(){
				var settings                 = defaultSettings();
				settings.normalizeSignatures = false;
				service.$property( propertyName = "settings", mock = settings );

				var a = service.compute( newLogEvent( message = "Order 123 failed" ) );
				var b = service.compute( newLogEvent( message = "Order 98765 failed" ) );
				expect( a ).notToBe( b );
			} );

			it( "hashes on category and message alone when there is no exception", function(){
				var a = service.compute( newLogEvent( message = "plain", extraInfo = { some : "context" } ) );
				var b = service.compute( newLogEvent( message = "plain", extraInfo = "other context" ) );
				expect( a ).toBe( b );
			} );
		} );
	}

}
