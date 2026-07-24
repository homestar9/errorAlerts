/**
 * Maps the test and module paths and starts a ColdBox virtual application.
 */
component {

	// Name the module used in CFML mappings.
	request.MODULE_NAME = "errorAlerts";
	// Name the module's repository directory.
	request.MODULE_PATH = "errorAlerts";

	// Configure the test application.
	this.name               = "#request.MODULE_NAME#-testing-suite";
	this.sessionManagement  = true;
	this.sessionTimeout     = createTimespan( 0, 0, 15, 0 );
	this.applicationTimeout = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies   = true;

	// Map the test directory.
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );

	// Map the harness application root.
	rootPath                 = reReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ] = rootPath;

	// Find and map the module repository.
	moduleRootPath = reReplaceNoCase(
		rootPath,
		"#request.MODULE_PATH#(\\|/)test-harness(\\|/)",
		""
	);
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = moduleRootPath & "#request.MODULE_PATH#";

	public boolean function onRequestStart( required targetPage ){
		// Allow enough time for the complete suite.
		setting requestTimeout   ="9999";
		// Create a virtual application for this request.
		request.coldBoxVirtualApp = new coldbox.system.testing.VirtualApp( appMapping = "/root" );

		// Start the virtual application for test runner and spec requests.
		if ( getBaseTemplatePath().replace( expandPath( "/tests" ), "" ).reFindNoCase( "(runner|specs)" ) ) {
			request.coldBoxVirtualApp.startup();
		}

		// Restart when the request asks for a framework reinitialization.
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
