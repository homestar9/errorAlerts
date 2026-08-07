/**
 * Shared settings and helpers for every build task.
 *
 * Finds the project root and reads build/build.json. It fills in missing values
 * and provides one settings struct to every build task. It also runs external
 * programs such as git and gh in the same way for every task.
 *
 * You should not need to edit this file. Everything a project changes lives in build.json.
 */
component {

	/**
	 * init
	 *
	 * Reads and validates the settings.
	 *
	 * @buildDir The build folder holding this file. Tasks pass
	 *           getDirectoryFromPath( getCurrentTemplatePath() ).
	 */
	function init( required string buildDir ){
		variables.buildDir = reReplace( arguments.buildDir, "[\\/]$", "" );
		// The project root is one level above the build folder.
		variables.root        = reReplace( variables.buildDir, "[\\/][^\\/]+$", "" );
		variables.binaryCache = {};
		// Track values set in build.json so derived defaults do not replace them.
		variables.touchedKeys = {};
		variables.settings    = loadSettings();
		return this;
	}

	/**
	 * getSettings
	 *
	 * Returns the whole settings struct.
	 */
	struct function getSettings(){
		return variables.settings;
	}

	/**
	 * get
	 *
	 * Returns one setting.
	 *
	 * @key          The setting name, for example "branch".
	 * @defaultValue What to return when the setting is missing.
	 */
	function get( required string key, defaultValue = "" ){
		return structKeyExists( variables.settings, arguments.key ) ? variables.settings[ arguments.key ] : arguments.defaultValue;
	}

	/**
	 * repoPath
	 *
	 * Turns a path relative to the project root into a full path.
	 *
	 * Do not rename this method to resolvePath. CommandBox already provides a
	 * resolvePath() that starts from the task file instead of the project root.
	 *
	 * @relative A path relative to the project root, for example "CHANGELOG.md".
	 */
	string function repoPath( required string relative ){
		return variables.root & "/" & arguments.relative;
	}

	/**
	 * buildPath
	 *
	 * Turns a path relative to the build folder into a full path.
	 *
	 * @relative A path relative to the build folder, for example "templates/RELEASE.md".
	 */
	string function buildPath( required string relative ){
		return variables.buildDir & "/" & arguments.relative;
	}

	/**
	 * getRoot
	 *
	 * Returns the full path of the project root.
	 */
	string function getRoot(){
		return variables.root;
	}

	/**
	 * boxJSON
	 *
	 * Reads and returns the project's box.json.
	 */
	struct function boxJSON(){
		var path = repoPath( "box.json" );
		if ( !fileExists( path ) ) {
			throw( type = "BuildConfig", message = "No box.json found at #path#. Run build tasks from a CommandBox package." );
		}
		return deserializeJSON( fileRead( path ) );
	}

	/**
	 * slug
	 *
	 * Returns the package slug from box.json, falling back to the package name.
	 */
	string function slug(){
		var box = boxJSON();
		return box.slug ?: ( box.name ?: "package" );
	}

	/**
	 * version
	 *
	 * Returns the version from box.json.
	 */
	string function version(){
		return boxJSON().version ?: "0.0.0";
	}

	/**
	 * execNative
	 *
	 * Runs an external program and returns its exit code and output.
	 * The method does not throw. Some callers expect a nonzero exit code as a
	 * valid result, such as a git check for a missing ref.
	 *
	 * Each argument is passed separately. Paths with spaces need no extra quotes.
	 *
	 * This plain component does not receive the CommandBox task helpers. Java
	 * starts the process directly instead. Shell features such as pipes,
	 * redirection, and wildcards are not available.
	 *
	 * @name The program name, for example "git".
	 * @args The arguments, for example [ "status", "--porcelain" ].
	 */
	struct function execNative( required string name, array args = [] ){
		var binary  = findBinary( arguments.name );
		var argList = createObject( "java", "java.util.ArrayList" ).init();
		argList.add( javaCast( "string", binary ) );
		for ( var arg in arguments.args ) {
			argList.add( javaCast( "string", arg ) );
		}

		try {
			var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( argList );
			builder.directory( createObject( "java", "java.io.File" ).init( variables.root ) );
			// Combine both output streams so callers can display one useful message.
			builder.redirectErrorStream( javaCast( "boolean", true ) );

			var process = builder.start();
			var reader  = createObject( "java", "java.io.BufferedReader" ).init(
				createObject( "java", "java.io.InputStreamReader" ).init( process.getInputStream() )
			);

			var output = createObject( "java", "java.lang.StringBuilder" ).init();
			var line   = reader.readLine();
			while ( !isNull( line ) ) {
				output.append( line ).append( chr( 10 ) );
				line = reader.readLine();
			}
			reader.close();

			return { exitCode : process.waitFor(), output : trim( output.toString() ) };
		} catch ( any e ) {
			// Exit code 127 lets callers identify a program that could not start.
			return {
				exitCode : 127,
				output   : "Could not run '#arguments.name#': #e.message#"
			};
		}
	}

	/**
	 * commandExists
	 *
	 * Reports whether a program can be found and run at all.
	 *
	 * @name The program name, for example "gh".
	 */
	boolean function commandExists( required string name ){
		// A found program has a full path; a missing one falls back to the bare name.
		return findBinary( arguments.name ) != arguments.name;
	}

	/**
	 * findBinary
	 *
	 * Returns the full path to a program when it can be found.
	 * Returns the bare name when the search fails so the system can try its own
	 * lookup and return a useful error.
	 *
	 * The path has no quotes because execNative() passes each argument separately.
	 *
	 * The search checks PATH and then common installation folders. The second
	 * search supports terminals whose PATH has not updated after an install.
	 *
	 * Results are remembered for the life of the task.
	 *
	 * @name The program name, for example "git", "gh".
	 */
	string function findBinary( required string name ){
		if ( structKeyExists( variables.binaryCache, arguments.name ) ) {
			return variables.binaryCache[ arguments.name ];
		}

		var jFile     = createObject( "java", "java.io.File" );
		var separator = jFile.separator;
		var resolved  = arguments.name;
		// The empty extension covers Mac and Linux; the rest are the Windows launchers.
		var extensions = [ "", ".exe", ".cmd", ".bat" ];

		var searchDirs = [];
		var pathEnv    = createObject( "java", "java.lang.System" ).getenv( "PATH" );
		if ( !isNull( pathEnv ) ) {
			searchDirs.append( listToArray( pathEnv, jFile.pathSeparator ), true );
		}
		searchDirs.append( wellKnownDirs(), true );

		for ( var dir in searchDirs ) {
			if ( !len( trim( dir ) ) ) {
				continue;
			}
			for ( var ext in extensions ) {
				var candidate = reReplace( dir, "[\\/]$", "" ) & separator & arguments.name & ext;
				if ( fileExists( candidate ) ) {
					resolved = candidate;
					break;
				}
			}
			if ( resolved != arguments.name ) {
				break;
			}
		}

		variables.binaryCache[ arguments.name ] = resolved;
		return resolved;
	}

	/******************************** Private helpers ********************************/

	/**
	 * wellKnownDirs
	 *
	 * The usual install folders to check when PATH does not turn up a program.
	 */
	private array function wellKnownDirs(){
		var sys  = createObject( "java", "java.lang.System" );
		var dirs = [];

		var programFiles   = sys.getenv( "ProgramFiles" );
		var programFilesX86 = sys.getenv( "ProgramFiles(x86)" );
		var localAppData   = sys.getenv( "LOCALAPPDATA" );

		if ( !isNull( programFiles ) ) {
			dirs.append( programFiles & "\GitHub CLI" );
			dirs.append( programFiles & "\Git\cmd" );
			dirs.append( programFiles & "\Git\bin" );
			dirs.append( programFiles & "\nodejs" );
		}
		if ( !isNull( programFilesX86 ) ) {
			dirs.append( programFilesX86 & "\GitHub CLI" );
			dirs.append( programFilesX86 & "\Git\cmd" );
		}
		if ( !isNull( localAppData ) ) {
			dirs.append( localAppData & "\Programs\GitHub CLI" );
			dirs.append( localAppData & "\Microsoft\WinGet\Links" );
			dirs.append( localAppData & "\Programs\Git\cmd" );
		}

		// Mac and Linux.
		dirs.append( "/usr/local/bin" );
		dirs.append( "/usr/bin" );
		dirs.append( "/bin" );
		dirs.append( "/opt/homebrew/bin" );
		dirs.append( "/opt/local/bin" );
		dirs.append( "/snap/bin" );

		return dirs;
	}

	/**
	 * loadSettings
	 *
	 * Builds settings from defaults and build.json, then validates the result.
	 */
	private struct function loadSettings(){
		var result   = defaults();
		var jsonPath = buildPath( "build.json" );

		if ( fileExists( jsonPath ) ) {
			var raw = trim( fileRead( jsonPath ) );
			if ( len( raw ) ) {
				var userSettings = "";
				try {
					userSettings = deserializeJSON( raw );
				} catch ( any e ) {
					throw(
						type    = "BuildConfig",
						message = "build/build.json is not valid JSON (#e.message#). Two common causes: a value left unquoted, and a single backslash. Backslashes must be doubled in JSON, so a regular expression looks like ""\\.avif$""."
					);
				}
				if ( !isStruct( userSettings ) ) {
					throw( type = "BuildConfig", message = "build/build.json must hold a JSON object, for example { ""branch"": ""main"" }." );
				}
				result = merge( result, userSettings );
			}
		}

		applyProjectTypeDefaults( result );
		fillDerivedDefaults( result );
		validate( result );
		return result;
	}

	/**
	 * defaults
	 *
	 * The settings used when build.json does not say otherwise.
	 */
	private struct function defaults(){
		return {
			"templateVersion" : "1.0.0",
			"projectType"     : "module",
			"branch"          : "main",
			"changelog"       : "CHANGELOG.md",
			// Empty means "work it out": box.json's testbox.runner, or the fallback below.
			"testRunner"      : "",
			"runTests"        : true,
			"gitSync"         : true,
			"requireCleanTree": true,
			"coldboxMapping"  : "test-harness/coldbox",
			"stagingDir"      : ".tmp",
			"artifactsDir"    : ".artifacts",
			"tagPrefix"       : "v",
			"publish"         : { "forgebox" : true, "github" : true },
			"excludes"        : defaultExcludes(),
			"excludesAdd"     : [],
			"engines"         : [],
			"warmup"          : { "attempts" : 60, "delaySeconds" : 5 }
		};
	}

	/**
	 * defaultExcludes
	 *
	 * Top-level files and folders kept out of the package.
	 *
	 * Each regular expression checks a top-level file or folder name. Matching is
	 * partial, so use anchors when needed. For example, `modules` also matches
	 * `modules_app`. Included folders are copied in full.
	 *
	 * Add to this list with "excludesAdd" in build.json rather than replacing it.
	 */
	private array function defaultExcludes(){
		return [
			// The build tooling never ships.
			"^[\\/]?build$",
			// CommandBox reinstalls dependencies from box.json.
			"^[\\/]?modules$",
			"^[\\/]?node_modules$",
			// Tests and their harness.
			"^[\\/]?test-harness$",
			"^[\\/]?tests$",
			"^[\\/]?test-results$",
			// Server definitions and local scratch.
			"server-.*\.json",
			"^[\\/]?temp$",
			"^[\\/]?plans$",
			// Notes for people and coding agents.
			"(AGENTS|CLAUDE|DEVNOTES|RELEASE)\.md",
			"\.bak$",
			// Exclude archives that could make the package much larger.
			"\.(zip|tar|tar\.gz|tgz|7z|rar)$",
			// Exclude hidden files and folders such as .git, .env, and .artifacts.
			"^[\\/]?\..*"
		];
	}

	/**
	 * applyProjectTypeDefaults
	 *
	 * Adjusts defaults for the project type.
	 * Application projects do not publish to ForgeBox unless build.json enables it.
	 *
	 * @settings The settings struct, changed in place.
	 */
	private void function applyProjectTypeDefaults( required struct settings ){
		// Keep an explicit publish.forgebox value from build.json.
		if ( lCase( arguments.settings.projectType ) == "app" && !userTouched( "publish.forgebox" ) ) {
			arguments.settings.publish.forgebox = false;
		}
	}

	/**
	 * fillDerivedDefaults
	 *
	 * Fills settings that can be read from the project.
	 * The test runner URL comes from box.json when build.json omits it.
	 *
	 * @settings The settings struct, changed in place.
	 */
	private void function fillDerivedDefaults( required struct settings ){
		if ( len( trim( arguments.settings.testRunner ) ) ) {
			return;
		}
		var box = "";
		try {
			box = boxJSON();
		} catch ( any e ) {
			box = {};
		}
		var runner = ( box.testbox.runner ?: "" );
		// testbox.runner is sometimes an array or struct of named runners. Take the first URL.
		if ( isArray( runner ) && arrayLen( runner ) ) {
			runner = isStruct( runner[ 1 ] ) ? ( runner[ 1 ].default ?: "" ) : runner[ 1 ];
		} else if ( isStruct( runner ) ) {
			for ( var key in runner ) {
				runner = runner[ key ];
				break;
			}
		}
		arguments.settings.testRunner = isSimpleValue( runner ) && len( trim( runner ) )
			? trim( runner )
			: "http://127.0.0.1:60299/tests/runner.cfm";
	}

	/**
	 * merge
	 *
	 * Merges one settings struct over another.
	 * Nested structs merge by key. Arrays replace the existing array as one value.
	 *
	 * @base    The starting struct.
	 * @overlay The values to lay over it.
	 */
	private struct function merge( required struct base, required struct overlay ){
		var result = duplicate( arguments.base );
		for ( var key in arguments.overlay ) {
			var incoming = arguments.overlay[ key ];
			if (
				structKeyExists( result, key )
				&& isStruct( result[ key ] )
				&& isStruct( incoming )
			) {
				result[ key ] = merge( result[ key ], incoming );
				for ( var sub in incoming ) {
					variables.touchedKeys[ key & "." & sub ] = true;
				}
			} else {
				result[ key ] = incoming;
				variables.touchedKeys[ key ] = true;
			}
		}
		return result;
	}

	/**
	 * userTouched
	 *
	 * Returns true when build.json set a key.
	 *
	 * @key The key, for example "publish.forgebox".
	 */
	private boolean function userTouched( required string key ){
		return structKeyExists( variables.touchedKeys ?: {}, arguments.key );
	}

	/**
	 * validate
	 *
	 * Validates settings before the build starts.
	 *
	 * @settings The settings struct to check.
	 */
	private void function validate( required struct settings ){
		var s = arguments.settings;

		if ( !listFindNoCase( "module,app", s.projectType ) ) {
			throw( type = "BuildConfig", message = "build.json projectType must be ""module"" or ""app"", not ""#s.projectType#""." );
		}
		if ( !len( trim( s.branch ) ) ) {
			throw( type = "BuildConfig", message = "build.json branch cannot be empty. Use the branch you release from, for example ""main""." );
		}
		if ( !len( trim( s.changelog ) ) ) {
			throw( type = "BuildConfig", message = "build.json changelog cannot be empty. Name your changelog file, for example ""CHANGELOG.md""." );
		}
		if ( !isBoolean( s.runTests ) ) {
			throw( type = "BuildConfig", message = "build.json runTests must be true or false." );
		}
		if ( !isStruct( s.publish ) || !structKeyExists( s.publish, "forgebox" ) || !structKeyExists( s.publish, "github" ) ) {
			throw( type = "BuildConfig", message = "build.json publish must look like { ""forgebox"": true, ""github"": true }." );
		}
		if ( !isBoolean( s.publish.forgebox ) || !isBoolean( s.publish.github ) ) {
			throw( type = "BuildConfig", message = "build.json publish.forgebox and publish.github must be true or false." );
		}
		if ( !isArray( s.excludes ) || !isArray( s.excludesAdd ) ) {
			throw( type = "BuildConfig", message = "build.json excludes and excludesAdd must be arrays of regular expressions." );
		}
		if ( !isArray( s.engines ) ) {
			throw( type = "BuildConfig", message = "build.json engines must be an array like [ { ""name"": ""Lucee 5"", ""configFile"": ""server-lucee@5.json"" } ]." );
		}
		for ( var engine in s.engines ) {
			if ( !isStruct( engine ) || !structKeyExists( engine, "configFile" ) ) {
				throw(
					type    = "BuildConfig",
					message = "Every entry in build.json engines needs a configFile, for example { ""name"": ""Lucee 5"", ""configFile"": ""server-lucee@5.json"" }."
				);
			}
		}
		if ( !isStruct( s.warmup ) || !isNumeric( s.warmup.attempts ?: "" ) || !isNumeric( s.warmup.delaySeconds ?: "" ) ) {
			throw( type = "BuildConfig", message = "build.json warmup must look like { ""attempts"": 60, ""delaySeconds"": 5 }." );
		}
		if ( !reFindNoCase( "^https?://", s.testRunner ) ) {
			throw( type = "BuildConfig", message = "build.json testRunner must be a full URL, for example ""http://127.0.0.1:60310/tests/runner.cfm""." );
		}
	}

	/**
	 * allExcludes
	 *
	 * The exclude list the build actually uses: the base list plus anything in excludesAdd.
	 */
	array function allExcludes(){
		var result = duplicate( variables.settings.excludes );
		result.append( variables.settings.excludesAdd, true );
		return result;
	}

	/**
	 * probeUrl
	 *
	 * Returns the site URL used to check whether the test server is running.
	 * Using the test runner URL would start the suite during the check.
	 */
	string function probeUrl(){
		return reReplaceNoCase( variables.settings.testRunner, "^(https?://[^/]+).*$", "\1" ) & "/";
	}
}
