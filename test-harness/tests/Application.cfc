/**
 * Test suite bootstrap: maps /root at the harness and /errorAlerts at the repo
 * root, then boots the ColdBox virtual application per request.
 */
component {

	// The name of the module used in cfmappings, etc.
	request.MODULE_NAME = "errorAlerts";
	// The directory name of the module on disk (the repo root folder name).
	request.MODULE_PATH = "errorAlerts";

	// APPLICATION CFC PROPERTIES
	this.name               = "#request.MODULE_NAME#-testing-suite";
	this.sessionManagement  = true;
	this.sessionTimeout     = createTimespan( 0, 0, 15, 0 );
	this.applicationTimeout = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies   = true;

	// Create testing mapping
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );

	// The application root
	rootPath                 = reReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ] = rootPath;

	// The module root path
	moduleRootPath = reReplaceNoCase(
		rootPath,
		"#request.MODULE_PATH#(\\|/)test-harness(\\|/)",
		""
	);
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = moduleRootPath & "#request.MODULE_PATH#";

	public boolean function onRequestStart( required targetPage ){
		// Set a high timeout for long running tests
		setting requestTimeout   ="9999";
		// New ColdBox Virtual Application Starter
		request.coldBoxVirtualApp = new coldbox.system.testing.VirtualApp( appMapping = "/root" );

		// If hitting the runner or specs, prep our virtual app
		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		// Reload for fresh results
		if ( url.keyExists( "fwreinit" ) ) {
			if ( server.keyExists( "lucee" ) ) {
				pagePoolClear();
			}
			request.coldBoxVirtualApp.restart();
		}

		return true;
	}

	public void function onRequestEnd( required targetPage ){
		request.coldBoxVirtualApp.shutdown();
	}

}
