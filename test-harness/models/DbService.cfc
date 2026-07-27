/**
 * DbService
 *
 * Runs the failing queries used by the database scenarios.
 *
 * Application.cfc declares two in-memory datasources because no engine here
 * ships both drivers: Adobe gets Derby from `cfpm install derby` and Lucee 6
 * bundles HSQLDB. This component tries each one once, keeps whichever
 * connects, and creates a small `orders` table to fail against.
 *
 * When neither driver is present, `getDatasource()` returns an empty string.
 * The Trigger handler checks that and falls back to the portable scenarios,
 * which still produce real database exceptions on any engine.
 */
component singleton {

	// A datasource name that was never declared, for the portable scenario.
	variables.UNDEFINED_DATASOURCE = "harnessDatasourceThatDoesNotExist";
	// Declared in Application.cfc pointing at a closed port.
	variables.DEAD_DATASOURCE      = "harnessDead";

	/**
	 * init
	 *
	 * Returns the service. The datasource choice is made on first use.
	 */
	function init(){
		return this;
	}

	/**
	 * getDatasource
	 *
	 * Returns the name of the working in-memory datasource, or an empty string
	 * when neither driver is installed. The answer is worked out once and kept.
	 */
	string function getDatasource(){
		if ( structKeyExists( variables, "datasource" ) ) {
			return variables.datasource;
		}

		variables.datasource  = "";
		variables.probeErrors = [];
		createDerbyDatabase();
		for ( var candidate in [ "harnessDerby", "harnessHsql" ] ) {
			if ( setupSchema( candidate ) ) {
				variables.datasource = candidate;
				break;
			}
		}

		return variables.datasource;
	}

	/**
	 * describe
	 *
	 * Returns a short line about which datasource is in use, for the catalog page.
	 * When nothing connected it includes why each one failed, because the usual
	 * cause is a missing JDBC driver and the message says so.
	 */
	string function describe(){
		var name = getDatasource();
		if ( name.len() ) {
			return "In-memory database ready on datasource '#name#'.";
		}
		return "No in-memory database. Run `cfpm install derby` on Adobe or use Lucee 6. The portable scenarios still work. Tried: "
		& variables.probeErrors.toList( " | " );
	}

	/**
	 * syntaxError
	 *
	 * Runs SQL the database cannot parse.
	 */
	function syntaxError(){
		return run( "SELCT * FRM orders WHERE" );
	}

	/**
	 * missingTable
	 *
	 * Selects from a table that was never created.
	 */
	function missingTable(){
		return run( "SELECT id, customer FROM orders_archive_2019" );
	}

	/**
	 * missingColumn
	 *
	 * Selects a column the table does not have.
	 */
	function missingColumn(){
		return run( "SELECT id, shipping_address FROM orders" );
	}

	/**
	 * constraintViolation
	 *
	 * Inserts a row whose primary key is already taken.
	 */
	function constraintViolation(){
		return run( "INSERT INTO orders (id, customer, total) VALUES (1, 'Duplicate Dan', 10.00)" );
	}

	/**
	 * transactionFailure
	 *
	 * Inserts one good row and one bad row inside a transaction, so the good row
	 * is rolled back when the second insert fails.
	 */
	function transactionFailure(){
		var ds = requireDatasource();

		transaction {
			try {
				queryExecute(
					"INSERT INTO orders (id, customer, total) VALUES (900, 'Rollback Rita', 25.00)",
					{},
					{ datasource : ds }
				);
				queryExecute(
					"INSERT INTO orders (id, customer, total) VALUES (1, 'Conflicting Carl', 25.00)",
					{},
					{ datasource : ds }
				);
				transactionCommit();
			} catch ( any e ) {
				transactionRollback();
				rethrow;
			}
		}
	}

	/**
	 * badParameter
	 *
	 * Binds text to an integer parameter.
	 */
	function badParameter(){
		return queryExecute(
			"SELECT id, customer FROM orders WHERE id = :id",
			{ id : { value : "not-a-number", cfsqltype : "cf_sql_integer" } },
			{ datasource : requireDatasource() }
		);
	}

	/**
	 * undefinedDatasource
	 *
	 * Queries a datasource name that was never declared. Works on every engine.
	 */
	function undefinedDatasource(){
		return queryExecute( "SELECT 1 FROM orders", {}, { datasource : variables.UNDEFINED_DATASOURCE } );
	}

	/**
	 * deadConnection
	 *
	 * Queries a datasource pointed at a closed port, so connecting fails.
	 * Uses a short timeout so the request does not hang.
	 */
	function deadConnection(){
		return queryExecute(
			"SELECT 1 FROM orders",
			{},
			{ datasource : variables.DEAD_DATASOURCE, timeout : 5 }
		);
	}

	/**
	 * run
	 *
	 * Runs a statement against the working datasource.
	 *
	 * @sql The statement to run.
	 */
	private function run( required string sql ){
		return queryExecute( arguments.sql, {}, { datasource : requireDatasource() } );
	}

	/**
	 * requireDatasource
	 *
	 * Returns the working datasource name or throws a clear message when no
	 * driver is installed. Without this the engine's own error would be about a
	 * missing datasource, which hides the real reason.
	 */
	private string function requireDatasource(){
		var name = getDatasource();
		if ( !name.len() ) {
			throw(
				type    = "Harness.Db.NoDriver",
				message = "No in-memory database driver is installed",
				detail  = "Run `cfpm install derby` on Adobe or start the Lucee 6 server. Until then use the portable database scenarios."
			);
		}
		return name;
	}

	/**
	 * createDerbyDatabase
	 *
	 * Creates the in-memory Derby database by opening one direct JDBC connection
	 * with `create=true`, then closing it.
	 *
	 * This is needed because Adobe builds the Derby url from a fixed template in
	 * WEB-INF/cfusion/lib/neo-drivers.xml and drops any extra keys, so there is
	 * no way to get `create=true` in from `this.datasources`. Without an existing
	 * database the datasource fails with "Database 'memory:harness' not found".
	 * Once the database exists in this JVM the datasource attaches to it fine.
	 *
	 * The driver object is used directly instead of DriverManager. cfpm installs
	 * Derby as an OSGi bundle, which never registers itself with DriverManager,
	 * so DriverManager.getConnection() answers "No suitable driver found".
	 *
	 * Failures are recorded and then ignored. When the driver is missing
	 * altogether the datasource probe reports that on its own.
	 */
	private void function createDerbyDatabase(){
		try {
			var driver = createObject( "java", "org.apache.derby.jdbc.EmbeddedDriver" ).init();
			var props  = createObject( "java", "java.util.Properties" ).init();
			driver.connect( "jdbc:derby:memory:harness;create=true", props ).close();
		} catch ( any e ) {
			variables.probeErrors.append( "derby create: #e.message#" );
		}
	}

	/**
	 * setupSchema
	 *
	 * Creates the orders table on a candidate datasource and confirms it can be
	 * read back. Returns false when the driver is missing or the database cannot
	 * be reached. A "table already exists" error is fine, so the create is run
	 * first and the select decides.
	 *
	 * @datasource The datasource name to try.
	 */
	private boolean function setupSchema( required string datasource ){
		try {
			queryExecute(
				"CREATE TABLE orders (
					id INT NOT NULL PRIMARY KEY,
					customer VARCHAR(100),
					total DECIMAL(10,2)
				)",
				{},
				{ datasource : arguments.datasource }
			);
			queryExecute(
				"INSERT INTO orders (id, customer, total) VALUES (1, 'Ada Lovelace', 149.99)",
				{},
				{ datasource : arguments.datasource }
			);
		} catch ( any e ) {
			// The table is probably already there. The select below settles it.
		}

		try {
			queryExecute( "SELECT id FROM orders", {}, { datasource : arguments.datasource } );
			return true;
		} catch ( any e ) {
			// Adobe's message is always "Error Executing Database Query.", so the
			// real reason is in detail.
			variables.probeErrors.append( "#arguments.datasource#: #e.message# #e.detail#" );
			return false;
		}
	}

}
