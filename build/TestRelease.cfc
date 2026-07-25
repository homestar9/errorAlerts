/**
 * The release-day test sweep: box run-script test:release
 *
 * Runs the full CFML suite on every supported engine, one after another. Run this by hand
 * BEFORE publish:release. It is deliberately not part of the release recipe itself: a flaky
 * engine boot should never abort a publish, and the recipe keeps its own fast, single-engine
 * test gate (Build.cfc runs the suite against whatever engine is up).
 *
 * All engines share port 60310, so the sweep is strictly sequential: stop everything, start one
 * engine, warm the app, run the suite, stop it, move on. Expect the whole run to take a while; a
 * first-ever boot of an engine also downloads it, which adds more.
 */
component {

	/**
	 * Constructor
	 */
	function init(){
		variables.testRunner = "http://127.0.0.1:60310/tests/runner.cfm";
		// Probe the harness root, never the runner: a bare GET of runner.cfm executes the whole
		// suite. 2xx/3xx from the root proves the server and the ColdBox app both answer.
		variables.probeUrl = "http://127.0.0.1:60310/";

		// The engines the module supports, in run order. Each entry is one server-*.json at the
		// repo root (the same files the start:* scripts in box.json use). The sweep aborts on
		// the first failure, so the least-proven engines go LAST: adobe@2023 and boxlang@1 are
		// the two most recently green (64/64), so they run first, and a Lucee environment problem
		// then still leaves you with results for the proven engines before it.
		variables.engines = [
			{ "name" : "Adobe 2023", "configFile" : "server-adobe@2023.json" },
			{ "name" : "BoxLang", "configFile" : "server-boxlang-cfml@1.json" },
			{ "name" : "Adobe 2025", "configFile" : "server-adobe@2025.json" },
			{ "name" : "Lucee 5", "configFile" : "server-lucee@5.json" },
			{ "name" : "Lucee 6", "configFile" : "server-lucee@6.json" }
		];

		// Warm-up budget per engine: attempts x delay. A cold ColdBox boot can take a while, so
		// be patient before declaring an engine dead.
		variables.warmupAttempts     = 60;
		variables.warmupDelaySeconds = 5;

		return this;
	}

	/**
	 * Run the sweep: every engine's CFML suite. Aborts on the first failure, naming the engine
	 * that failed and listing what had already passed. Leaves all servers stopped either way.
	 */
	function run(){
		var passed  = [];
		var started = getTickCount();

		// Only one server can own port 60310, and we do not know which engine (if any) is up.
		stopAllEngines();

		for ( var engine in variables.engines ) {
			var engineStart = getTickCount();
			print.line().boldBlueLine( "=== #engine.name# (#engine.configFile#) ===" ).toConsole();

			startEngine( engine, passed );
			warmUp( engine, passed );

			print.blueLine( "Running the CFML suite on #engine.name#..." ).toConsole();
			var suiteFailed = false;
			try {
				command( "testbox run" )
					.params( runner = variables.testRunner, verbose = false )
					.run();
				suiteFailed = ( shell.getExitCode() != 0 );
			} catch ( any e ) {
				suiteFailed = true;
			}

			stopEngine( engine.configFile );

			if ( suiteFailed ) {
				return failSweep( "The CFML suite FAILED on #engine.name#.", passed );
			}

			var minutes = numberFormat( ( getTickCount() - engineStart ) / 60000, "0.9" );
			passed.append( "#engine.name# (#minutes# min)" );
			print.boldGreenLine( "#engine.name#: suite green in #minutes# min." ).toConsole();
		}

		var totalMinutes = numberFormat( ( getTickCount() - started ) / 60000, "0.9" );
		print
			.line()
			.boldGreenLine( "test:release sweep GREEN in #totalMinutes# min: #passed.toList( ', ' )#" )
			.toConsole();
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * Start one engine's server and abort the sweep if the start command itself fails.
	 *
	 * @engine The engine struct (name + configFile)
	 * @passed What has already passed, for the failure summary
	 */
	private function startEngine( required struct engine, required array passed ){
		var startFailed = false;
		try {
			command( "server start" )
				.params( serverConfigFile = arguments.engine.configFile )
				.run();
			startFailed = ( shell.getExitCode() != 0 );
		} catch ( any e ) {
			startFailed = true;
		}
		if ( startFailed ) {
			failSweep( "#arguments.engine.name# failed to start (server start #arguments.engine.configFile#).", arguments.passed );
		}
	}

	/**
	 * Poll the harness root until the app answers, so the suite never runs against a server
	 * that is still booting (the known ColdBox mid-load race reads as bogus failures). Aborts
	 * the sweep when the budget runs out. Never touches runner.cfm with ?fwreinit=true - that
	 * 500s on Adobe.
	 *
	 * @engine The engine struct (name + configFile)
	 * @passed What has already passed, for the failure summary
	 */
	private function warmUp( required struct engine, required array passed ){
		print.blueLine( "Warming up #arguments.engine.name# (up to #variables.warmupAttempts * variables.warmupDelaySeconds# seconds)..." ).toConsole();
		var lastStatus = 0;
		for ( var attempt = 1; attempt <= variables.warmupAttempts; attempt++ ) {
			var httpResult = "";
			try {
				cfhttp(
					url          = variables.probeUrl,
					method       = "GET",
					timeout      = 60,
					throwonerror = false,
					redirect     = false,
					result       = "local.httpResult"
				);
				lastStatus = val( httpResult.statuscode ?: "0" );
			} catch ( any e ) {
				lastStatus = 0;
			}
			// 2xx and 3xx both mean the app is up (the harness root may redirect).
			if ( lastStatus >= 200 && lastStatus < 400 ) {
				print.greenLine( "#arguments.engine.name# is up (status #lastStatus#)." ).toConsole();
				return;
			}
			sleep( variables.warmupDelaySeconds * 1000 );
		}

		stopEngine( arguments.engine.configFile );
		failSweep(
			"#arguments.engine.name# never became ready (last status: #lastStatus#). "
			& "A repeating 500 usually means the app itself will not boot on this engine - start it by hand and read the log "
			& "(box run-script logs:...).",
			arguments.passed
		);
	}

	/**
	 * Stop every known engine, ignoring failures - at most one of them is actually running,
	 * and `server stop` on a stopped server just complains.
	 */
	private function stopAllEngines(){
		print.blueLine( "Stopping any running engine on port 60310..." ).toConsole();
		for ( var engine in variables.engines ) {
			stopEngine( engine.configFile );
		}
	}

	/**
	 * Stop one server quietly. A failure here never matters: either the server was not running,
	 * or the next start will complain about the busy port anyway.
	 *
	 * @configFile The server-*.json file for the engine to stop
	 */
	private function stopEngine( required string configFile ){
		try {
			command( "server stop" ).params( serverConfigFile = arguments.configFile ).run();
		} catch ( any e ) {
			// Not running - nothing to do.
		}
	}

	/**
	 * Abort the sweep with what failed and what had already passed, so a long run that dies on a
	 * late engine still tells you which engines were green.
	 *
	 * @message What failed
	 * @passed The parts that already passed
	 */
	private function failSweep( required string message, required array passed ){
		var summary = arguments.passed.len()
			? "Already green before the failure: #arguments.passed.toList( ', ' )#."
			: "Nothing had passed yet.";
		return error( arguments.message & " " & summary );
	}
}
