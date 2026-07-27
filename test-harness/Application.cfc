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

	/* Declare an in-memory database for the query-failure scenarios. No engine
	 * here ships both drivers: Adobe gets Derby from `cfpm install derby` and
	 * Lucee 6 bundles HSQLDB. Declaring a datasource whose driver is missing
	 * costs nothing until something queries it, so DbService probes both and
	 * uses whichever connects.
	 *
	 * The two engines spell the JDBC url differently. Adobe wants `url` plus
	 * `driver : "other"`, and Lucee wants `connectionString`. Sending Adobe an
	 * unknown key logs "Unsupported attributes found in URL for datasource", so
	 * the struct is built per engine. */
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
		/* Adobe reaches its Derby driver through the named "Apache Derby Embedded"
		 * type. Going through driver "other" with the same class times out,
		 * because cfpm installs Derby as an OSGi bundle that the generic JDBC
		 * path cannot see.
		 *
		 * Adobe builds the url from the template `jdbc:derby:[database];
		 * create=[isnewdb];[args]` in WEB-INF/cfusion/lib/neo-drivers.xml. So
		 * `isnewdb` is what creates the database, and putting "memory:" in front
		 * of the name keeps the whole thing in RAM with nothing written to disk.
		 * Leaving isnewdb out produces `create=;`, which Derby rejects and which
		 * shows up as a connection timeout. */
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
