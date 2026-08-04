/**
 * Tests how stack frames are classified as application or framework code.
 */
component extends="tests.resources.BaseUnitSpec" {

	function run(){
		describe( "FrameClassifier", function(){
			beforeEach( function(){
				settings   = defaultSettings();
				classifier = prepareMock( new errorAlerts.models.FrameClassifier() );
				classifier.$property( propertyName = "settings", mock = settings );

				var controllerStub = createStub();
				controllerStub.$( "getAppRootPath", "/app/" );
				classifier.$property( propertyName = "coldbox", mock = controllerStub );
			} );

			it( "classifies the conventional ColdBox source folders as application code", function(){
				expect( classifier.isApplicationFrame( "/app/handlers/Posts.cfc" ) ).toBeTrue();
				expect( classifier.isApplicationFrame( "/app/models/PostService.cfc" ) ).toBeTrue();
				expect( classifier.isApplicationFrame( "/app/views/posts/_card.cfm" ) ).toBeTrue();
				expect( classifier.isApplicationFrame( "/app/modules_app/blog/handlers/Posts.cfc" ) ).toBeTrue();
			} );

			it( "does not classify installed modules as application code", function(){
				expect( classifier.isApplicationFrame( "/app/modules/quick/models/BaseEntity.cfc" ) ).toBeFalse();
			} );

			it( "does not classify paths outside the application root", function(){
				expect( classifier.isApplicationFrame( "/coldbox/system/EventHandler.cfc" ) ).toBeFalse();
				expect( classifier.isApplicationFrame( "" ) ).toBeFalse();
			} );

			it( "never classifies database driver frames", function(){
				expect( classifier.isApplicationFrame( "|SQLServer|6.0.0.1282|" ) ).toBeFalse();
			} );

			it( "normalizes Windows backslash paths before matching", function(){
				var winStub = createStub();
				winStub.$( "getAppRootPath", "C:\sites\app\" );
				classifier.$property( propertyName = "coldbox", mock = winStub );

				expect( classifier.appRelativePath( "C:\sites\app\views\home.cfm" ) ).toBe( "/views/home.cfm" );
				expect( classifier.isApplicationFrame( "C:\sites\app\views\home.cfm" ) ).toBeTrue();
			} );

			it( "supports custom prefixes for non-conventional source folders", function(){
				settings.applicationFramePrefixes = [ "/src/" ];

				expect( classifier.isApplicationFrame( "/app/src/Thing.cfc" ) ).toBeTrue();
				expect( classifier.isApplicationFrame( "/app/handlers/Posts.cfc" ) ).toBeFalse();
			} );

			it( "finds the first application frame and reports its raw position", function(){
				var found = classifier.findFirstApplicationFrame( [
					{ template : "/app/modules/qb/models/BaseGrammar.cfc", line : 128 },
					{ template : "|SQLServer|6.0.0.1282|", line : 1085 },
					{ template : "/app/views/posts/_card.cfm", line : 14 },
					{ template : "/app/handlers/Posts.cfc", line : 8 }
				] );

				expect( found.index ).toBe( 3, "the first match wins, later ones are ignored" );
				expect( found.template ).toBe( "/app/views/posts/_card.cfm" );
				expect( found.line ).toBe( 14 );
			} );

			it( "returns an empty struct when no frame qualifies within maxScan", function(){
				expect(
					classifier.findFirstApplicationFrame( [ { template : "/coldbox/system/Bootstrap.cfc", line : 1 } ] )
				).toBeEmpty();

				expect(
					classifier.findFirstApplicationFrame(
						[
							{ template : "/coldbox/system/Bootstrap.cfc", line : 1 },
							{ template : "/app/handlers/Posts.cfc", line : 8 }
						],
						1
					)
				).toBeEmpty( "the match sits past the scan limit" );
			} );

			it( "returns an empty relative path when the root is unknown", function(){
				var brokenStub = createStub();
				brokenStub.$(
					method         = "getAppRootPath",
					throwException = true,
					throwType      = "NoApp",
					throwMessage   = "no app context"
				);
				classifier.$property( propertyName = "coldbox", mock = brokenStub );

				expect( classifier.appRelativePath( "/app/handlers/Posts.cfc" ) ).toBe( "" );
				expect( classifier.isApplicationFrame( "/app/handlers/Posts.cfc" ) ).toBeFalse();
			} );
		} );
	}

}
