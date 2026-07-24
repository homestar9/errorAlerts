/**
 * Test harness bootstrap. Standard ColdBox module-tester Application.cfc:
 * maps /moduleroot at the repo root so config/Coldbox.cfc can register the
 * module under test straight from the working copy.
 */
component {

	// The module under test
	request.MODULE_NAME = "errorAlerts";

	// Application properties
	this.name              = hash( getCurrentTemplatePath() );
	this.sessionManagement = true;
	this.sessionTimeout    = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies  = true;

	// COLDBOX STATIC PROPERTY, DO NOT CHANGE UNLESS THIS IS NOT THE ROOT OF YOUR COLDBOX APP
	COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() );
	// The web server mapping to this application. Used for remote purposes or static purposes
	COLDBOX_APP_MAPPING   = "";
	// COLDBOX PROPERTIES
	COLDBOX_CONFIG_FILE   = "";
	// COLDBOX APPLICATION KEY OVERRIDE
	COLDBOX_APP_KEY       = "";

	// Mappings
	this.mappings[ "/root" ] = COLDBOX_APP_ROOT_PATH;

	// Map back to the repo root, where the module under test lives
	moduleRootPath = reReplaceNoCase(
		this.mappings[ "/root" ],
		"#request.MODULE_NAME#(\\|/)test-harness(\\|/)",
		""
	);
	modulePath = reReplaceNoCase( this.mappings[ "/root" ], "test-harness(\\|/)", "" );

	// Module Root + Path Mappings
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = modulePath;

	// application start
	public boolean function onApplicationStart(){
		application.cbBootstrap = new coldbox.system.Bootstrap(
			COLDBOX_CONFIG_FILE,
			COLDBOX_APP_ROOT_PATH,
			COLDBOX_APP_KEY,
			COLDBOX_APP_MAPPING
		);
		application.cbBootstrap.loadColdbox();
		return true;
	}

	// request start
	public boolean function onRequestStart( string targetPage ){
		if ( url.keyExists( "fwreinit" ) && server.keyExists( "lucee" ) ) {
			pagePoolClear();
		}

		// Process ColdBox Request
		application.cbBootstrap.onRequestStart( arguments.targetPage );

		return true;
	}

	public void function onSessionStart(){
		application.cbBootStrap.onSessionStart();
	}

	public void function onSessionEnd( struct sessionScope, struct appScope ){
		arguments.appScope.cbBootStrap.onSessionEnd( argumentCollection = arguments );
	}

	public boolean function onMissingTemplate( template ){
		return application.cbBootstrap.onMissingTemplate( argumentCollection = arguments );
	}

}
