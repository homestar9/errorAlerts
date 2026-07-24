/**
 * Builds and verifies the errorAlerts release package.
 *
 * See docs/release-process.md for the packaging safeguards.
 */
component {

	/**
	 * init
	 *
	 * Sets the build paths, exclusions, and empty output directories.
	 */
	function init(){
		// Set the build paths.
		variables.cwd          = getCWD().reReplace( "\.$", "" );
		variables.artifactsDir = cwd & "/.artifacts";
		variables.buildDir     = cwd & "/.tmp";
		// Use the IPv4 address because Windows can resolve localhost to IPv6
		// while CommandBox listens only on IPv4.
		variables.testRunner   = "http://127.0.0.1:60310/tests/runner.cfm";

		/**
		 * Lists top-level entries to exclude from the package.
		 *
		 * See docs/release-process.md before changing these expressions.
		 */
		variables.excludes = [
			"^[\\/]?build$",
			// CommandBox installs modules from box.json.
			"^[\\/]?modules$",
			"^[\\/]?test-harness$",
			"^[\\/]?test-results$",
			"server-.*\.json",
			"(AGENTS|CLAUDE|DEVNOTES)\.md",
			"\.bak$",
			// Do not copy archives into the release package.
			"\.(zip|tar|tar\.gz|tgz|7z|rar)$",
			// Exclude every top-level hidden file and directory.
			"^[\\/]?\..*"
		];

		// Recreate the build output directories.
		[
			variables.buildDir,
			variables.artifactsDir
		].each( function( item ){
			if ( directoryExists( item ) ) {
				directoryDelete( item, true );
			}
			directoryCreate( item, true, true );
		} );

		// Map the installed ColdBox source for the build task.
		fileSystemUtil.createMapping( "coldbox", variables.cwd & "test-harness/coldbox" );

		return this;
	}

	/**
	 * run
	 *
	 * Runs the tests, builds the package, and creates checksum files.
	 *
	 * @projectName The project name used for resources and slugs.
	 * @version     The version to build.
	 * @buildID     The build identifier.
	 * @branch      The branch to build. When blank, uses the current branch.
	 */
	function run(
		required projectName,
		version = "1.0.0",
		buildID = createUUID(),
		branch  = ""
	){
		if ( !len( trim( arguments.branch ) ) ) {
			arguments.branch = getCurrentBranch();
		}

		// Confirm the test server is available before running the suite.
		ensureTestRunnerReachable();
		runTests();

		// Map the project for the build task.
		fileSystemUtil.createMapping( arguments.projectName, variables.cwd );

		// Build and verify the package.
		buildSource( argumentCollection = arguments );

		// Create checksum files for the zip.
		buildChecksums();

		print
			.line()
			.boldMagentaLine( "Build Process is done! Enjoy your build!" )
			.toConsole();
	}

	/**
	 * runTests
	 *
	 * Runs the test suite and stops the build when a test fails.
	 */
	function runTests(){
		print.blueLine( "Testing the package, please wait..." ).toConsole();

		command( "testbox run" )
			.params( runner = variables.testRunner, verbose = false )
			.run();

		if ( shell.getExitCode() ) {
			return error( "Cannot continue building, tests failed!" );
		}
	}

	/**
	 * buildSource
	 *
	 * Copies, stamps, packages, and verifies the module source.
	 *
	 * @projectName The project name used for resources and slugs.
	 * @version     The version to build.
	 * @buildID     The build identifier.
	 * @branch      The branch to build.
	 */
	function buildSource(
		required projectName,
		version = "1.0.0",
		buildID = createUUID(),
		branch  = ""
	){
		if ( !len( trim( arguments.branch ) ) ) {
			arguments.branch = getCurrentBranch();
		}

		print
			.line()
			.boldMagentaLine(
				"Building #arguments.projectName# v#arguments.version#+#arguments.buildID# from #cwd# using the #arguments.branch# branch."
			)
			.toConsole();

		ensureExportDir( argumentCollection = arguments );

		// Create the staging directory.
		variables.projectBuildDir = variables.buildDir & "/#projectName#";
		directoryCreate( variables.projectBuildDir, true, true );

		// Copy the source into the staging directory.
		print.blueLine( "Copying source to build folder..." ).toConsole();
		copy( variables.cwd, variables.projectBuildDir );

		// Add the build marker file.
		fileWrite(
			"#variables.projectBuildDir#/#projectName#-#version#+#buildID#",
			"Built with love on #dateTimeFormat( now(), "full" )#"
		);

		// Replace version and build placeholders.
		print.greenLine( "Updating version identifier to #arguments.version#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "/#variables.projectBuildDir#/**",
				token       = "@build.version@",
				replacement = arguments.version
			)
			.run();

		print.greenLine( "Updating build identifier to #arguments.buildID#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "/#variables.projectBuildDir#/**",
				token       = ( arguments.branch == "main" ? "@build.number@" : "+@build.number@" ),
				replacement = ( arguments.branch == "main" ? arguments.buildID : "-snapshot" )
			)
			.run();

		// Create and verify the zip.
		var destination = "#variables.exportsDir#/#projectName#-#version#.zip";
		print.greenLine( "Zipping code to #destination#" ).toConsole();
		cfzip(
			action    = "zip",
			file      = "#destination#",
			source    = "#variables.projectBuildDir#",
			overwrite = true,
			recurse   = true
		);

		verifyZip( destination );

		// Copy box.json next to the zip.
		fileCopy( "#variables.projectBuildDir#/box.json", variables.exportsDir );
	}

	/**
	 * getCurrentBranch
	 *
	 * Reads the branch from .git/HEAD without calling Git.
	 * Returns "main" when HEAD cannot provide a branch name.
	 */
	private function getCurrentBranch(){
		var headFile = variables.cwd & ".git/HEAD";
		if ( !fileExists( headFile ) ) {
			return "main";
		}
		var head = trim( fileRead( headFile ) );
		if ( left( head, 16 ) == "ref: refs/heads/" ) {
			return replace( head, "ref: refs/heads/", "" );
		}
		return "main";
	}

	/**
	 * ensureTestRunnerReachable
	 *
	 * Stops the build when the test server cannot be reached.
	 * Checks the web root because requesting runner.cfm would run the tests.
	 */
	private function ensureTestRunnerReachable(){
		var probeUrl   = reReplaceNoCase( variables.testRunner, "/tests/runner\.cfm.*$", "/" );
		var httpResult = "";
		try {
			cfhttp(
				url          = probeUrl,
				method       = "GET",
				timeout      = 15,
				throwonerror = false,
				redirect     = false,
				result       = "local.httpResult"
			);
		} catch ( any e ) {
			httpResult = { statuscode : "0" };
		}
		var statusCode = val( httpResult.statuscode ?: "0" );
		if ( statusCode < 200 || statusCode >= 400 ) {
			return error(
				"Test server unreachable at #probeUrl# (status #statusCode#). "
				& "Start a server first (box run-script start:2023) and retry. "
				& "To package source WITHOUT running tests, invoke target=buildSource explicitly."
			);
		}
	}

	/**
	 * buildChecksums
	 *
	 * Creates SHA-512 and MD5 checksum files next to the zip.
	 */
	private function buildChecksums(){
		print.greenLine( "Building checksums" ).toConsole();
		command( "checksum" )
			.params(
				path      = "#variables.exportsDir#/*.zip",
				algorithm = "SHA-512",
				extension = "sha512",
				write     = true
			)
			.run();
		command( "checksum" )
			.params(
				path      = "#variables.exportsDir#/*.zip",
				algorithm = "md5",
				extension = "md5",
				write     = true
			)
			.run();
	}

	/**
	 * verifyZip
	 *
	 * Stops the build when the zip and staging directory have different counts.
	 * See docs/release-process.md for why this check is required.
	 *
	 * @zipPath The absolute path to the new zip.
	 */
	private function verifyZip( required string zipPath ){
		cfzip( action = "list", file = arguments.zipPath, name = "local.zipEntries" );

		var stagedCount = directoryList( variables.projectBuildDir, true, "path" )
			.filter( function( item ){
				return fileExists( item );
			} )
			.len();

		// Count only files because cfzip also returns directory rows.
		var zippedCount = 0;
		for ( var row in local.zipEntries ) {
			if ( row.type == "file" ) {
				zippedCount++;
			}
		}

		if ( zippedCount != stagedCount ) {
			return error(
				"Zip is incomplete: staged #stagedCount# files but the zip holds #zippedCount#. "
				& "Check .gitignore and variables.excludes for a pattern that is eating source files. "
				& "Staging dir: #variables.projectBuildDir#"
			);
		}

		print.greenLine( "Verified zip contains all #zippedCount# staged files." ).toConsole();
	}

	/**
	 * copy
	 *
	 * Copies top-level entries that do not match variables.excludes.
	 *
	 * @src     The source directory.
	 * @target  The target directory.
	 * @recurse An unused compatibility argument.
	 */
	private function copy( src, target, recurse = true ){
		directoryList(
			src,
			false,
			"path",
			function( path ){
				var isExcluded = false;
				variables.excludes.each( function( item ){
					if ( path.replaceNoCase( variables.cwd, "", "all" ).reFindNoCase( item ) ) {
						isExcluded = true;
					}
				} );
				return !isExcluded;
			}
		).each( function( item ){
			if ( fileExists( item ) ) {
				print.blueLine( "Copying #item#" ).toConsole();
				fileCopy( item, target );
			} else {
				print.greenLine( "Copying directory #item#" ).toConsole();
				directoryCopy( item, target & "/" & item.replace( src, "" ), true );
			}
		} );
	}

	/**
	 * ensureExportDir
	 *
	 * Creates the versioned artifact directory when needed.
	 *
	 * @projectName The project name.
	 * @version     The version being built.
	 */
	private function ensureExportDir( required projectName, version = "1.0.0" ){
		if ( structKeyExists( variables, "exportsDir" ) && directoryExists( variables.exportsDir ) ) {
			return;
		}
		variables.exportsDir = variables.artifactsDir & "/#projectName#/#arguments.version#";
		directoryCreate( variables.exportsDir, true, true );
	}

}
