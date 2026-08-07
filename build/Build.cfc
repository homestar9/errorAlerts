/**
 * Builds and checks the release package.
 *
 * Run it with: box run-script build:package
 *
 * Runs tests, copies the included source, stamps the version, creates the zip,
 * checks its file count, and writes checksums. Output goes to
 * .artifacts/<slug>/<version>/.
 *
 * Settings come from build/build.json. You should not need to edit this file.
 */
component {

	/**
	 * init
	 *
	 * Loads the settings and empties the output folders.
	 */
	function init(){
		variables.config = new BuildConfig( getDirectoryFromPath( getCurrentTemplatePath() ) );
		variables.s      = variables.config.getSettings();
		variables.root   = variables.config.getRoot();

		variables.buildDir     = variables.root & "/" & variables.s.stagingDir;
		variables.artifactsDir = variables.root & "/" & variables.s.artifactsDir;

		// Remove old output so it cannot enter the new package.
		[ variables.buildDir, variables.artifactsDir ].each( function( item ){
			if ( directoryExists( item ) ) {
				directoryDelete( item, true );
			}
			directoryCreate( item, true, true );
		} );

		// Map an installed ColdBox copy when project components need it during a build.
		if ( len( trim( variables.s.coldboxMapping ) ) ) {
			var coldboxPath = variables.root & "/" & variables.s.coldboxMapping;
			if ( directoryExists( coldboxPath ) ) {
				fileSystemUtil.createMapping( "coldbox", coldboxPath );
			}
		}

		return this;
	}

	/**
	 * run
	 *
	 * Runs the tests, builds the package, and writes checksums.
	 *
	 * @projectName The name used for the package folder and zip. Defaults to the box.json slug.
	 * @version     The version being built. Defaults to the box.json version.
	 * @buildID     The build identifier. When blank, uses the short git commit hash.
	 * @branch      The branch being built. When blank, reads the current branch.
	 * @skipTests   Skip the test suite for this run only. Use only when this version has already
	 *              been tested. It prints a warning, because an untested build is a real risk.
	 */
	function run(
		string projectName = "",
		string version     = "",
		string buildID     = "",
		string branch      = "",
		boolean skipTests  = false
	){
		fillDefaults( arguments );

		if ( arguments.skipTests || !variables.s.runTests ) {
			var reason = arguments.skipTests ? "asked for with skipTests" : "turned off in build.json";
			print
				.line()
				.boldYellowLine( "WARNING: the test suite was skipped (#reason#)." )
				.yellowLine( "This package has not been tested by this build." )
				.line()
				.toConsole();
		} else {
			ensureTestRunnerReachable();
			runTests();
		}

		// Map the project so a build can load the project's own components if it needs to.
		fileSystemUtil.createMapping( arguments.projectName, variables.root );

		buildSource( argumentCollection = arguments );
		buildChecksums();

		print.line().boldMagentaLine( "Build finished. The package is in #variables.exportsDir#" ).toConsole();
	}

	/**
	 * runTests
	 *
	 * Runs the test suite and stops the build when anything fails.
	 */
	function runTests(){
		print.blueLine( "Running the test suite, please wait..." ).toConsole();

		command( "testbox run" )
			.params( runner = variables.s.testRunner, verbose = false )
			.run();

		if ( shell.getExitCode() ) {
			return error( "Stopping: the tests failed. Fix them, or use skipTests to build anyway." );
		}
	}

	/**
	 * buildSource
	 *
	 * Copies, stamps, packages, and verifies the source.
	 *
	 * @projectName The name used for the package folder and zip.
	 * @version     The version being built.
	 * @buildID     The build identifier.
	 * @branch      The branch being built.
	 * @skipTests   Accepted so this can be called with the same arguments as run().
	 */
	function buildSource(
		string projectName = "",
		string version     = "",
		string buildID     = "",
		string branch      = "",
		boolean skipTests  = false
	){
		fillDefaults( arguments );

		print
			.line()
			.boldMagentaLine(
				"Building #arguments.projectName# #arguments.version#+#arguments.buildID# from the #arguments.branch# branch."
			)
			.toConsole();

		ensureExportDir( arguments.projectName, arguments.version );

		variables.projectBuildDir = variables.buildDir & "/#arguments.projectName#";
		directoryCreate( variables.projectBuildDir, true, true );

		print.blueLine( "Copying source into the staging folder..." ).toConsole();
		copy( variables.root, variables.projectBuildDir );

		// Leave a note naming the commit this package was built from.
		fileWrite(
			"#variables.projectBuildDir#/#arguments.projectName#-#arguments.version#+#arguments.buildID#",
			"Built from commit #arguments.buildID# on #dateTimeFormat( now(), "full" )#"
		);

		// Release builds use the build ID. Other branches are marked as snapshots.
		print.greenLine( "Stamping version #arguments.version#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "#variables.projectBuildDir#/**",
				token       = "@build.version@",
				replacement = arguments.version
			)
			.run();

		var isReleaseBranch = ( arguments.branch == variables.s.branch );
		print.greenLine( "Stamping build identifier #arguments.buildID#" ).toConsole();
		command( "tokenReplace" )
			.params(
				path        = "#variables.projectBuildDir#/**",
				token       = ( isReleaseBranch ? "@build.number@" : "+@build.number@" ),
				replacement = ( isReleaseBranch ? arguments.buildID : "-snapshot" )
			)
			.run();

		var destination = "#variables.exportsDir#/#arguments.projectName#-#arguments.version#.zip";
		print.greenLine( "Zipping to #destination#" ).toConsole();
		cfzip(
			action    = "zip",
			file      = "#destination#",
			source    = "#variables.projectBuildDir#",
			overwrite = true,
			recurse   = true
		);

		verifyZip( destination );

		// Put a copy of box.json beside the zip so you can read what shipped without unzipping.
		fileCopy( "#variables.projectBuildDir#/box.json", variables.exportsDir );
	}

	/******************************** Private helpers ********************************/

	/**
	 * fillDefaults
	 *
	 * Fills blank arguments from box.json and git.
	 *
	 * @args The argument struct, changed in place.
	 */
	private void function fillDefaults( required struct args ){
		if ( !len( trim( arguments.args.projectName ?: "" ) ) ) {
			arguments.args.projectName = variables.config.slug();
		}
		if ( !len( trim( arguments.args.version ?: "" ) ) ) {
			arguments.args.version = variables.config.version();
		}
		if ( !len( trim( arguments.args.branch ?: "" ) ) ) {
			arguments.args.branch = getCurrentBranch();
		}
		if ( !len( trim( arguments.args.buildID ?: "" ) ) ) {
			arguments.args.buildID = getCurrentCommit();
		}
	}

	/**
	 * getCurrentBranch
	 *
	 * Reads the current branch from .git/HEAD without running git.
	 * Uses the configured release branch when the repository data is unavailable.
	 */
	private string function getCurrentBranch(){
		var headFile = variables.root & "/.git/HEAD";
		if ( !fileExists( headFile ) ) {
			return variables.s.branch;
		}
		var head = trim( fileRead( headFile ) );
		if ( left( head, 16 ) == "ref: refs/heads/" ) {
			return replace( head, "ref: refs/heads/", "" );
		}
		// A detached HEAD holds a commit hash, not a branch name.
		return variables.s.branch;
	}

	/**
	 * getCurrentCommit
	 *
	 * Reads the short commit hash from the .git folder.
	 * Returns "nocommit" when repository data is unavailable.
	 */
	private string function getCurrentCommit(){
		var headFile = variables.root & "/.git/HEAD";
		if ( !fileExists( headFile ) ) {
			return "nocommit";
		}
		var head = trim( fileRead( headFile ) );
		var sha  = "";

		if ( left( head, 5 ) == "ref: " ) {
			// The usual case: HEAD names a branch, and the hash sits in .git/<ref>, or in
			// .git/packed-refs once git has tidied it away.
			var ref     = trim( mid( head, 6, len( head ) ) );
			var refFile = variables.root & "/.git/" & ref;
			if ( fileExists( refFile ) ) {
				sha = trim( fileRead( refFile ) );
			} else {
				var packedFile = variables.root & "/.git/packed-refs";
				if ( fileExists( packedFile ) ) {
					for ( var rawLine in listToArray( fileRead( packedFile ), chr( 10 ) ) ) {
						var line = trim( rawLine );
						// Each line reads "<hash> <ref>". Skip comments and peeled tag lines.
						if ( len( line ) && left( line, 1 ) != "##" && left( line, 1 ) != "^" && right( line, len( ref ) ) == ref ) {
							sha = listFirst( line, " " );
							break;
						}
					}
				}
			}
		} else {
			// A detached HEAD already holds the hash.
			sha = head;
		}

		return len( sha ) ? left( sha, 7 ) : "nocommit";
	}

	/**
	 * ensureTestRunnerReachable
	 *
	 * Stops the build when the test server does not answer.
	 * The check uses the site root because requesting the runner starts the suite.
	 */
	private function ensureTestRunnerReachable(){
		var probeUrl   = variables.config.probeUrl();
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
		// Anything in the 200s or 300s means the site answered.
		var statusCode = val( httpResult.statuscode ?: "0" );
		if ( statusCode < 200 || statusCode >= 400 ) {
			return error(
				"No answer from the test server at #probeUrl# (status #statusCode#). "
				& "Start a server first, then run this again. "
				& "To build without running the tests, add :skipTests=true."
			);
		}
	}

	/**
	 * buildChecksums
	 *
	 * Writes SHA-512 and MD5 files next to the zip so anyone can confirm a download is intact.
	 */
	private function buildChecksums(){
		print.greenLine( "Writing checksums" ).toConsole();
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
	 * Stops the build when the zip contains fewer files than the staging folder.
	 * This catches any packaging rule that silently drops files.
	 *
	 * @zipPath The full path of the zip just written.
	 */
	private function verifyZip( required string zipPath ){
		cfzip( action = "list", file = arguments.zipPath, name = "local.zipEntries" );

		var stagedCount = directoryList( variables.projectBuildDir, true, "path" )
			.filter( function( item ){
				return fileExists( item );
			} )
			.len();

		// A zip lists folders as entries too, so only count the files.
		var zippedCount = 0;
		for ( var row in local.zipEntries ) {
			if ( row.type == "file" ) {
				zippedCount++;
			}
		}

		if ( zippedCount != stagedCount ) {
			return error(
				"The zip is incomplete: #stagedCount# files were staged but the zip holds #zippedCount#. "
				& "Check .gitignore and the excludes in build/build.json for a rule matching source files. "
				& "Staging folder: #variables.projectBuildDir#"
			);
		}

		print.greenLine( "Checked: the zip holds all #zippedCount# staged files." ).toConsole();
	}

	/**
	 * copy
	 *
	 * Copies included project files into the staging folder.
	 * A custom copy is used because Lucee does not apply directoryCopy filters reliably.
	 *
	 * Only top-level names are tested. Included folders are copied in full.
	 *
	 * @src    The folder to copy from.
	 * @target The folder to copy into.
	 */
	private function copy( required string src, required string target ){
		var excludes = variables.config.allExcludes();
		// A local variable keeps the target available inside the closures below.
		var targetDir = arguments.target;

		directoryList(
			arguments.src,
			false,
			"path",
			function( path ){
				var isExcluded = false;
				var name       = relativeName( path );
				excludes.each( function( pattern ){
					if ( name.reFindNoCase( pattern ) ) {
						isExcluded = true;
					}
				} );
				return !isExcluded;
			}
		).each( function( item ){
			var name = relativeName( item );
			if ( fileExists( item ) ) {
				print.blueLine( "  copy #name#" ).toConsole();
				fileCopy( item, targetDir );
			} else {
				print.greenLine( "  copy folder #name#" ).toConsole();
				directoryCopy( item, targetDir & "/" & name, true );
			}
		} );
	}

	/**
	 * relativeName
	 *
	 * Returns a path relative to the project root.
	 * Both paths use the same separators before comparison.
	 *
	 * @path The full path to shorten.
	 */
	private string function relativeName( required string path ){
		var normalisedPath = replace( arguments.path, "\", "/", "all" );
		var normalisedRoot = replace( variables.root, "\", "/", "all" );

		var name = replaceNoCase( normalisedPath, normalisedRoot, "", "one" );
		// Drop the separators left at either end.
		return reReplace( reReplace( name, "^[\\/]+", "" ), "[\\/]+$", "" );
	}

	/**
	 * ensureExportDir
	 *
	 * Creates .artifacts/<name>/<version>/ and remembers it for the rest of the build.
	 *
	 * @projectName The package name.
	 * @version     The version being built.
	 */
	private function ensureExportDir( required string projectName, required string version ){
		if ( structKeyExists( variables, "exportsDir" ) && directoryExists( variables.exportsDir ) ) {
			return;
		}
		variables.exportsDir = variables.artifactsDir & "/#arguments.projectName#/#arguments.version#";
		directoryCreate( variables.exportsDir, true, true );
	}
}
