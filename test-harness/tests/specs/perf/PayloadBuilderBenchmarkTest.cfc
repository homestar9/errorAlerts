/**
 * Measures PayloadBuilder.build() with large inputs.
 *
 * Debug output contains the measured times. The generous limits catch major
 * regressions without failing because of normal engine timing changes.
 *
 *   /tests/runner.cfm?directory=tests.specs.perf&reporter=text
 */
component extends="tests.resources.BaseUnitSpec" {

	// Report the minimum after warm-up and the average across all runs.
	variables.ITERATIONS = 5;

	// This high limit catches unbounded walking or full large-value serialization.
	variables.CEILING_MS = 10000;

	/**
	 * run
	 *
	 * Defines PayloadBuilder performance scenarios.
	 */
	function run(){
		describe( "PayloadBuilder benchmarks", function(){
			beforeEach( function(){
				settings   = defaultSettings();
				classifier = prepareMock( new errorAlerts.models.FrameClassifier() );
				classifier.$property( propertyName = "settings", mock = settings );
				classifier.$property( propertyName = "coldbox", mock = benchControllerStub() );
				builder = prepareMock( new errorAlerts.models.PayloadBuilder() );
				builder.$property( propertyName = "settings", mock = settings );
				builder.$property( propertyName = "coldbox", mock = benchControllerStub() );
				builder.$property( propertyName = "frameClassifier", mock = classifier );
				builder.$property( propertyName = "threadClassifier", mock = new errorAlerts.models.ThreadClassifier() );
			} );

			it( "(a) extraInfo containing one 5 MB base64-style string", function(){
				var blob = repeatString( "QmFzZTY0IFBERiBkYXRhIQ==", 218454 ); // ~5.2 MB
				var info = { "fileName" : "contract.pdf", "fileContent" : blob };

				var timing = timeScenario( "a: 5 MB string in extraInfo", function(){
					builder.build( newLogEvent( extraInfo = info ), "sig-a", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(b) extraInfo with a 20,000-key flat struct", function(){
				var wide = structNew( "ordered" );
				for ( var i = 1; i <= 20000; i++ ) {
					wide[ "field#i#" ] = "value #i#";
				}

				var timing = timeScenario( "b: 20,000-key flat struct", function(){
					builder.build( newLogEvent( extraInfo = wide ), "sig-b", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(c) extraInfo nested ten levels deep with arrays", function(){
				var deep = { "leaf" : "bottom" };
				for ( var i = 1; i <= 10; i++ ) {
					deep = { "level#i#" : deep, "items#i#" : [ "one", "two", "three" ] };
				}

				var timing = timeScenario( "c: depth-10 nested structs", function(){
					builder.build( newLogEvent( extraInfo = deep ), "sig-c", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(d) rc with 100 keys including complex values", function(){
				var rc = structNew( "ordered" );
				for ( var i = 1; i <= 100; i++ ) {
					if ( i % 10 == 0 ) {
						rc[ "filter#i#" ] = { "status" : "active", "page" : i, "tags" : [ "a", "b", "c" ] };
					} else {
						rc[ "field#i#" ] = repeatString( "v", 150 );
					}
				}
				builder.$property( propertyName = "coldbox", mock = benchControllerStub( rc ) );

				var timing = timeScenario( "d: rc with 100 keys", function(){
					builder.build( newLogEvent(), "sig-d", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(e) 500 KB JSON request body", function(){
				makePublic( builder, "buildBody" );
				var rows = [];
				for ( var i = 1; i <= 2000; i++ ) {
					rows.append( { "id" : i, "name" : "row #i#", "notes" : repeatString( "n", 200 ) } );
				}
				var httpData = {
					headers : { "Content-Type" : "application/json" },
					content : serializeJSON( { "rows" : rows } ) // ~500 KB
				};

				var timing = timeScenario( "e: 500 KB JSON body", function(){
					builder.buildBody( httpData );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(f) small baseline payload, the overhead floor", function(){
				var info = { "orderId" : 42, "statusCode" : 500, "correlationId" : "abc-123" };

				var timing = timeScenario( "f: small baseline payload", function(){
					builder.build( newLogEvent( extraInfo = info ), "sig-f", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(g) 5 MB string with a 17-entry maskKeys and 2 wildcard patterns", function(){
				settings.maskKeys = [
					"password", "passwd", "token", "secret", "apikey", "api_key",
					"authorization", "creditcard", "cvv", "ssn", "ssnLast4",
					"cardNumber", "expDate", "cardholderName", "client_secret",
					"auth", "profile"
				];
				// Inert on the old engine; priced by the new one.
				settings.maskKeyPatterns = [ "*socialsecurity*", "*cardnumber*" ];

				var blob = repeatString( "QmFzZTY0IFBERiBkYXRhIQ==", 218454 );
				var info = {
					"fileName"    : "contract.pdf",
					"fileContent" : blob,
					"password"    : "must-be-masked",
					"context"     : { "client_secret" : "also-masked", "statusCode" : 500 }
				};

				var timing = timeScenario( "g: 5 MB string, real-world mask config", function(){
					builder.build( newLogEvent( extraInfo = info ), "sig-g", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );

			it( "(h) 1,000 structs sharing 10 keys against 100 mask keys and 10 patterns", function(){
				// The worst case for per-node key matching: every node pays the
				// key check, and the same ten key names repeat 1,000 times.
				var bigList = [];
				for ( var i = 1; i <= 99; i++ ) {
					bigList.append( "maskedField#i#" );
				}
				bigList.append( "password" );
				settings.maskKeys = bigList;
				// Inert on the old engine; priced by the new one.
				settings.maskKeyPatterns = [
					"*secret1*", "*secret2*", "*secret3*", "*secret4*", "*secret5*",
					"*secret6*", "*secret7*", "*secret8*", "*secret9*", "*socialsecurity*"
				];

				var rows = [];
				for ( var i = 1; i <= 1000; i++ ) {
					var row = structNew( "ordered" );
					for ( var k = 1; k <= 9; k++ ) {
						row[ "column#k#" ] = "value #i#-#k#";
					}
					row[ "password" ] = "row-secret-#i#";
					rows.append( row );
				}

				var timing = timeScenario( "h: 1,000 x 10 keys, 100 mask keys + 10 patterns", function(){
					builder.build( newLogEvent( extraInfo = { "rows" : rows } ), "sig-h", 1 );
				} );

				expect( timing.avg ).toBeLT( variables.CEILING_MS );
			} );
		} );
	}

	/**
	 * timeScenario
	 *
	 * Runs a scenario several times and returns its minimum and average duration.
	 * The method also writes both values to TestBox debug output.
	 *
	 * @label    The scenario name shown in the debug output.
	 * @scenario The zero-argument closure to time.
	 */
	private struct function timeScenario( required string label, required any scenario ){
		var times = [];
		for ( var i = 1; i <= variables.ITERATIONS; i++ ) {
			var started = getTickCount();
			arguments.scenario();
			times.append( getTickCount() - started );
		}

		var total = 0;
		var best  = times[ 1 ];
		for ( var t in times ) {
			total += t;
			if ( t < best ) {
				best = t;
			}
		}
		var timing = { min : best, avg : int( total / times.len() ) };

		debug( "BENCHMARK #arguments.label#: min #timing.min# ms, avg #timing.avg# ms over #variables.ITERATIONS# runs (#times.toList( ', ' )# ms)" );
		return timing;
	}

	/**
	 * benchControllerStub
	 *
	 * Builds the controller stub needed by PayloadBuilder benchmarks.
	 * It provides a request context, application settings, and module registry.
	 *
	 * @rc The request collection the stubbed context returns.
	 */
	private any function benchControllerStub( struct rc = {} ){
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
		requestServiceStub.$( "contextExists", true );
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
