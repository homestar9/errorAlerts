/**
 * Build process for the errorAlerts module. Copied from the caffeinecms build
 * and trimmed: no docs target, smaller exclude list. The zip-entry-count guard
 * stays -- it is what catches an ignore pattern eating source files before a
 * broken package ships.
 */
component {

	/**
	 * Constructor: pathing, excludes, and clean build directories.
	 */
	function init(){
		// Setup Pathing
		variables.cwd          = getCWD().reReplace( "\.$", "" );
		variables.artifactsDir = cwd & "/.artifacts";
		variables.buildDir     = cwd & "/.tmp";
		// 127.0.0.1, not localhost: on Windows localhost can resolve to IPv6 ::1
		// while CommandBox binds the IPv4 loopback, and the runner preflight then
		// times out against a server that is actually up.
		variables.testRunner   = "http://127.0.0.1:60310/tests/runner.cfm";

		/**
		 * Source excludes NOT added to the final package.
		 *
		 * These are regex patterns run through reFindNoCase() against each
		 * top-level entry name in copy() below. reFindNoCase does a PARTIAL
		 * match, so anchor anything whose name is a prefix of something that
		 * must ship. Only TOP-LEVEL entries are tested; a directory that
		 * survives is copied whole.
		 *
		 * Keep shipping: box.json, ModuleConfig.cfc, README.md, changelog.md,
		 * config/, models/, interceptors/
		 */
		variables.excludes = [
			"^[\\/]?build$",
			// Dependencies: CommandBox reinstalls modules/ from box.json on install.
			"^[\\/]?modules$",
			"^[\\/]?test-harness$",
			"^[\\/]?test-results$",
			"server-.*\.json",
			"(AGENTS|CLAUDE|DEVNOTES)\.md",
			"\.bak$",
			// Nothing we ship is an archive; a stray zip once bloated a caffeinecms build 6x.
			"\.(zip|tar|tar\.gz|tgz|7z|rar)$",
			// Every dotfile/dotdir (.git, .env, .artifacts, .tmp, ...)
			"^[\\/]?\..*"
		];

		// Cleanup + Init Build Directories
		[
			variables.buildDir,
			variables.artifactsDir
		].each( function( item ){
			if ( directoryExists( item ) ) {
				directoryDelete( item, true );
			}
			directoryCreate( item, true, true );
		} );

		// Create Mappings
		fileSystemUtil.createMapping( "coldbox", variables.cwd & "test-harness/coldbox" );

		return this;
	}

	/**
	 * Run the build process: test, build source, checksums.
	 *
	 * @projectName The project name used for resources and slugs
	 * @version     The version you are building
	 * @buildID     The build identifier
	 * @branch      The branch you are building. Empty resolves the CURRENT git
	 *              branch at build time so the artifact metadata never lies.
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

		// Certify before packaging: a release build must never skip its tests.
		// The preflight makes an unreachable server abort with an ACCURATE
		// message (server down != test regression).
		ensureTestRunnerReachable();
		runTests();

		// Create project mapping
		fileSystemUtil.createMapping( arguments.projectName, variables.cwd );

		// Build the source
		buildSource( argumentCollection = arguments );

		// checksums
		buildChecksums();

		print
			.line()
			.boldMagentaLine( "Build Process is done! Enjoy your build!" )
			.toConsole();
	}

	/**
	 * Run the test suites and abort the build on any failure.
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
	 * Build the source: copy the slim module tree, stamp versions, zip, verify.
	 *
	 * @projectName The project name used for resources and slugs
	 * @version     The version you are building
	 * @buildID     The build identifier
	 * @branch      The branch you are building
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

		// Project Build Dir
		variables.projectBuildDir = variables.buildDir & "/#projectName#";
		directoryCreate( variables.projectBuildDir, true, true );

		// Copy source
		print.blueLine( "Copying source to build folder..." ).toConsole();
		copy( variables.cwd, variables.projectBuildDir );

		// Create build ID
		fileWrite(
			"#variables.projectBuildDir#/#projectName#-#version#+#buildID#",
			"Built with love on #dateTimeFormat( now(), "full" )#"
		);

		// Updating Placeholders
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

		// zip up source
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

		// Copy box.json for convenience
		fileCopy( "#variables.projectBuildDir#/box.json", variables.exportsDir );
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * Resolve the git branch by reading .git/HEAD directly (no git binary
	 * dependency). Returns "main" when HEAD is unreadable or detached, which
	 * only influences the version-token stamping.
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
	 * Abort with an accurate message when the TestBox HTTP runner is
	 * unreachable. Probes the harness web root, NOT runner.cfm -- a bare GET of
	 * the runner executes the whole suite and times the probe out.
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
	 * Build SHA-512 and MD5 checksums next to the zip.
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
	 * Abort the build if the zip does not contain every file staged for it.
	 * Deliberately dumb counting: it catches ANY ignore pattern, exclude regex,
	 * or zip quirk that eats source, which is exactly how caffeinecms
	 * 1.0.0-beta.1 shipped broken.
	 *
	 * @zipPath Absolute path to the zip that was just written
	 */
	private function verifyZip( required string zipPath ){
		cfzip( action = "list", file = arguments.zipPath, name = "local.zipEntries" );

		var stagedCount = directoryList( variables.projectBuildDir, true, "path" )
			.filter( function( item ){
				return fileExists( item );
			} )
			.len();

		// cfzip lists directories as their own rows, so only count the "file" ones.
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
	 * DirectoryCopy with top-level excludes (directoryCopy is broken in Lucee).
	 *
	 * @src     The source directory
	 * @target  The target directory
	 * @recurse Recurse into subdirectories
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
	 * Ensure the export directory exists at .artifacts/NAME/VERSION/
	 *
	 * @projectName The project name
	 * @version     The version being built
	 */
	private function ensureExportDir( required projectName, version = "1.0.0" ){
		if ( structKeyExists( variables, "exportsDir" ) && directoryExists( variables.exportsDir ) ) {
			return;
		}
		variables.exportsDir = variables.artifactsDir & "/#projectName#/#arguments.version#";
		directoryCreate( variables.exportsDir, true, true );
	}

}
