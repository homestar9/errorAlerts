/**
 * Starts the ColdBox test harness and maps the module from the working tree.
 */
component {

	// Name the module under test.
	request.MODULE_NAME = "errorAlerts";

	// Configure the test application.
	this.name              = hash( getCurrentTemplatePath() );
	this.sessionManagement = true;
	this.sessionTimeout    = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies  = true;

	// ColdBox uses this directory as the application root.
	COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() );
	// Use the web root as the application mapping.
	COLDBOX_APP_MAPPING   = "";
	// Use the default ColdBox configuration file.
	COLDBOX_CONFIG_FILE   = "";
	// Use ColdBox's default application key.
	COLDBOX_APP_KEY       = "";

	// Map the test harness as /root.
	this.mappings[ "/root" ] = COLDBOX_APP_ROOT_PATH;

	// Find the repository and module paths from the harness path.
	moduleRootPath = reReplaceNoCase(
		this.mappings[ "/root" ],
		"#request.MODULE_NAME#(\\|/)test-harness(\\|/)",
		""
	);
	modulePath = reReplaceNoCase( this.mappings[ "/root" ], "test-harness(\\|/)", "" );

	// Map the repository and module working tree.
	this.mappings[ "/moduleroot" ]            = moduleRootPath;
	this.mappings[ "/#request.MODULE_NAME#" ] = modulePath;

	// Start ColdBox with the application.
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

	// Pass each request to ColdBox.
	public boolean function onRequestStart( string targetPage ){
		if ( url.keyExists( "fwreinit" ) && server.keyExists( "lucee" ) ) {
			pagePoolClear();
		}

		// Process the current request.
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
