/**
 * Starts the ColdBox test harness and maps the module from the working tree.
 */
component {

	// Store the module name for mappings and ColdBox configuration.
	request.MODULE_NAME = "errorAlerts";

	// Keep sessions available for request and security scenarios.
	this.name              = hash( getCurrentTemplatePath() );
	this.sessionManagement = true;
	this.sessionTimeout    = createTimespan( 0, 0, 15, 0 );
	this.setClientCookies  = true;

	// Point ColdBox at the test harness.
	COLDBOX_APP_ROOT_PATH = getDirectoryFromPath( getCurrentTemplatePath() );
	// Use the web root as the application mapping.
	COLDBOX_APP_MAPPING   = "";
	// Use the default ColdBox configuration file.
	COLDBOX_CONFIG_FILE   = "";
	// Use ColdBox's default application key.
	COLDBOX_APP_KEY       = "";

	// Map the test harness as /root.
	this.mappings[ "/root" ] = COLDBOX_APP_ROOT_PATH;

	/* Declare in-memory databases for query failure scenarios. Adobe can use
	 * Derby, while Lucee 6 includes HSQLDB. DbService tries both and keeps the
	 * datasource that connects.
	 *
	 * Adobe uses `url` with `driver : "other"`. Lucee uses `connectionString`.
	 * Build a different struct for each engine to avoid unsupported keys. */
	if ( server.keyExists( "lucee" ) ) {
		this.datasources[ "harnessDerby" ] = {
			class            : "org.apache.derby.jdbc.EmbeddedDriver",
			connectionString : "jdbc:derby:memory:harness;create=true",
			username         : "",
			password         : ""
		};
		this.datasources[ "harnessHsql" ] = {
			class            : "org.hsqldb.jdbcDriver",
			connectionString : "jdbc:hsqldb:mem:harness",
			username         : "sa",
			password         : ""
		};
		// Points at a closed port so connecting always fails.
		this.datasources[ "harnessDead" ] = {
			class            : "org.apache.derby.jdbc.ClientDriver",
			connectionString : "jdbc:derby://127.0.0.1:1/harness",
			username         : "",
			password         : ""
		};
	} else {
		/* Adobe must use the named Apache Derby Embedded driver. The generic JDBC
		 * path cannot see the OSGi bundle installed by cfpm.
		 *
		 * The `memory:` database name keeps all data in RAM. args adds create=true
		 * so Derby creates the database before the datasource connects. */
		this.datasources[ "harnessDerby" ] = {
			driver   : "Apache Derby Embedded",
			database : "memory:harness",
			args     : "create=true",
			username : "",
			password : ""
		};
		this.datasources[ "harnessHsql" ] = {
			driver   : "other",
			class    : "org.hsqldb.jdbcDriver",
			url      : "jdbc:hsqldb:mem:harness",
			username : "sa",
			password : ""
		};
		// Points at a closed port so connecting always fails.
		this.datasources[ "harnessDead" ] = {
			driver   : "other",
			class    : "org.apache.derby.jdbc.ClientDriver",
			url      : "jdbc:derby://127.0.0.1:1/harness",
			username : "",
			password : ""
		};
	}

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

	/**
	 * onApplicationStart
	 *
	 * Starts ColdBox with the test harness configuration.
	 */
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

	/**
	 * onRequestStart
	 *
	 * Passes each request to ColdBox.
	 *
	 * @targetPage The requested CFML template.
	 */
	public boolean function onRequestStart( string targetPage ){
		if ( url.keyExists( "fwreinit" ) && server.keyExists( "lucee" ) ) {
			pagePoolClear();
		}

		/* The startFail legacy scenario throws here, inside an Application.cfc
		 * event method. Adobe wraps such an exception before onError() sees it,
		 * so this is the path that proves the module unwraps it. */
		if ( arguments.targetPage.findNoCase( "/legacy/startFail.cfm" ) ) {
			throw(
				type    = "Harness.StartFail",
				message = "Thrown from onRequestStart for a legacy page",
				detail  = "Adobe delivers this to onError() wrapped in an EventHandlerException."
			);
		}

		application.cbBootstrap.onRequestStart( arguments.targetPage );

		return true;
	}

	/**
	 * onError
	 *
	 * Reports exceptions from pages that run outside ColdBox, such as the
	 * legacy scenarios, then renders a short error page. ColdBox handles its
	 * own request exceptions before they can reach this method. This is the
	 * recipe the README documents for a legacy folder that shares the
	 * application.
	 *
	 * @exception The exception the engine passed to onError().
	 * @eventName The Application.cfc method that was running, or an empty string.
	 */
	public void function onError( required any exception, string eventName = "" ) output="true"{
		try {
			var reinitInProgress = structKeyExists( application, "fwReinit" ) && application.fwReinit;
			if ( !reinitInProgress && structKeyExists( application, "cbController" ) ) {
				application.cbController
					.getWireBox()
					.getInstance( "CaptureService@errorAlerts" )
					.captureException( arguments.exception );
			}
		} catch ( any e ) {
			// The alert must never replace the error page.
		}

		try {
			cfheader( statusCode = 500 );
		} catch ( any e ) {
		}

		var type = "";
		try {
			type = arguments.exception.type;
		} catch ( any e ) {
		}

		writeOutput(
			"<h1>Harness error page (outside ColdBox)</h1>" &
			"<p>Application.cfc onError() caught <code>#encodeForHtml( type )#</code>" &
			"#( len( arguments.eventName ) ? " while running <code>" & encodeForHtml( arguments.eventName ) & "</code>" : "" )#" &
			" and asked errorAlerts to report it.</p>" &
			"<p><a href=""/main/lastMail"">Read the alert</a> or <a href=""/"">return to the catalog</a>.</p>"
		);
	}

	/**
	 * onSessionStart
	 *
	 * Passes new sessions to ColdBox.
	 */
	public void function onSessionStart(){
		application.cbBootStrap.onSessionStart();
	}

	/**
	 * onSessionEnd
	 *
	 * Passes completed sessions to ColdBox.
	 *
	 * @sessionScope The session that ended.
	 * @appScope     The current application scope.
	 */
	public void function onSessionEnd( struct sessionScope, struct appScope ){
		arguments.appScope.cbBootStrap.onSessionEnd( argumentCollection = arguments );
	}

	/**
	 * onMissingTemplate
	 *
	 * Lets ColdBox handle a missing template.
	 *
	 * @template The requested template path.
	 */
	public boolean function onMissingTemplate( template ){
		return application.cbBootstrap.onMissingTemplate( argumentCollection = arguments );
	}

}
