/**
 * Release helpers for the publish:release recipe (build/release.boxr).
 *
 * Two targets, run at opposite ends of the recipe:
 *
 *   preflight — every check that should stop a release BEFORE anything irreversible happens
 *               (before `git checkout -f` can discard work, and before ForgeBox gets the zip).
 *   github    — runs AFTER a successful ForgeBox publish: creates the version tag, pushes it,
 *               and creates a GitHub Release with notes from changelog.md and the built zip
 *               plus its checksum attached.
 *
 * Both take the version from the recipe via :version=`package show version`, so the version
 * lives in exactly one place: box.json.
 */
component {

	/**
	 * Everything that must be true before a release is allowed to start. Each check aborts the
	 * recipe with a plain-English fix. Ordering note for the recipe: this runs BEFORE
	 * `git checkout -f main`, because -f silently throws away uncommitted changes, and the
	 * clean-tree check here is what makes that safe.
	 *
	 * @version The version being released, e.g. 1.0.0 (from `package show version`)
	 */
	function preflight( required string version ){
		// 1. Clean working tree. `git status --porcelain` prints one line per change; empty
		//    output means clean. This must pass before the recipe's `git checkout -f`.
		var status = execNative( "git status --porcelain" );
		if ( status.exitCode != 0 ) {
			return error( "Could not run git (#status.output#). Is this a git checkout?" );
		}
		if ( len( trim( status.output ) ) ) {
			return error(
				"Working tree is not clean. Commit or stash first, then re-run. Changes:" & chr( 10 ) & status.output
			);
		}

		// 2. Releases only cut from main.
		var branch = execNative( "git rev-parse --abbrev-ref HEAD" );
		if ( trim( branch.output ) != "main" ) {
			return error( "Releases are cut from main, but you are on '#trim( branch.output )#'." );
		}

		// 3. The version must not already be tagged. rev-parse exits non-zero when the tag does
		//    not exist, which is the good case here.
		var tagCheck = execNative( "git rev-parse -q --verify refs/tags/v#arguments.version#" );
		if ( tagCheck.exitCode == 0 ) {
			return error(
				"Tag v#arguments.version# already exists, so this version has already been released. "
				& "Bump the version in box.json first."
			);
		}

		// 4. changelog.md must have a section for this version. This is what forces the
		//    changelog to be written BEFORE a release can ship; the same section becomes the
		//    GitHub Release notes in github() below.
		extractChangelogSection( arguments.version );

		// 5. The gh CLI must be present and logged in. Checking now, rather than letting the
		//    github target discover it, avoids a half-released state where ForgeBox has the
		//    version but GitHub has no tag or release.
		var ghCheck = execNative( "gh auth status" );
		if ( ghCheck.exitCode != 0 ) {
			return error(
				"The GitHub CLI is missing or not logged in (run `gh auth login`). "
				& "Aborting BEFORE the ForgeBox publish so the two stay in sync. Detail: #ghCheck.output#"
			);
		}

		print.greenLine( "Preflight passed: clean tree on main, v#arguments.version# is unreleased, changelog entry found, gh is ready." ).toConsole();
	}

	/**
	 * The GitHub half of the release. The recipe calls this only after `publish` succeeded, so
	 * every failure message below assumes ForgeBox already has the version and tells you how to
	 * finish by hand instead of re-running the whole recipe.
	 *
	 * @version The version just published, e.g. 1.0.0 (from `package show version`)
	 * @notesOnly When true, just print the release notes that WOULD be used and stop. No tag,
	 *            no push, no GitHub Release. Lets you verify the changelog extraction safely.
	 */
	function github( required string version, boolean notesOnly = false ){
		var tagName = "v#arguments.version#";
		var slug    = deserializeJSON( fileRead( repoPath( "box.json" ) ) ).slug;

		// Release notes come from this version's changelog.md section (preflight already
		// proved it exists, but notesOnly can run standalone, so extract defensively).
		var notes = extractChangelogSection( arguments.version );
		if ( arguments.notesOnly ) {
			print.line().boldLine( "Release notes for #tagName#:" ).line( notes ).toConsole();
			return;
		}

		// The artifact the build just produced. It is attached to the GitHub Release along with
		// its SHA-512 checksum, so every release carries an immutable copy of exactly what went
		// to ForgeBox. GitHub release assets are free (no storage or bandwidth charge; the only
		// limit is 2 GiB per file). To stop attaching them, delete the two paths from the
		// `gh release create` command below.
		var zipPath = repoPath( ".artifacts/#slug#/#arguments.version#/#slug#-#arguments.version#.zip" );
		var shaPath = zipPath & ".sha512";
		if ( !fileExists( zipPath ) ) {
			return error(
				"Built zip not found at #zipPath#. The build step should have produced it; "
				& "run `box run-script build:module` and then `task run taskFile=build/Release.cfc target=github :version=#arguments.version#`."
			);
		}

		// gh reads the notes from a file so the markdown survives shell quoting untouched.
		var notesFile = repoPath( ".tmp/release-notes.md" );
		if ( !directoryExists( getDirectoryFromPath( notesFile ) ) ) {
			directoryCreate( getDirectoryFromPath( notesFile ), true, true );
		}
		fileWrite( notesFile, notes );

		// Tag the release. Everything after this point names the manual recovery steps, because
		// ForgeBox already has the version and a re-run of the recipe would refuse at preflight.
		print.blueLine( "Tagging #tagName#..." ).toConsole();
		var result = execNative( "git tag #tagName#" );
		if ( result.exitCode != 0 ) {
			return error( "Could not create tag #tagName#: #result.output#" );
		}

		print.blueLine( "Pushing main and #tagName# to origin..." ).toConsole();
		result = execNative( "git push origin main" );
		if ( result.exitCode != 0 ) {
			return error(
				"Push failed (#result.output#). ForgeBox already has #arguments.version#. Finish by hand:" & chr( 10 )
				& "  git push origin main && git push origin #tagName#" & chr( 10 )
				& "  gh release create #tagName# --title #tagName# --notes-file .tmp/release-notes.md #prereleaseFlag( arguments.version )# ""#zipPath#"" ""#shaPath#"""
			);
		}
		result = execNative( "git push origin #tagName#" );
		if ( result.exitCode != 0 ) {
			return error(
				"Tag push failed (#result.output#). ForgeBox already has #arguments.version#. Finish by hand:" & chr( 10 )
				& "  git push origin #tagName#" & chr( 10 )
				& "  gh release create #tagName# --title #tagName# --notes-file .tmp/release-notes.md #prereleaseFlag( arguments.version )# ""#zipPath#"" ""#shaPath#"""
			);
		}

		print.blueLine( "Creating GitHub Release #tagName#..." ).toConsole();
		result = execNative(
			"gh release create #tagName# --title #tagName# --notes-file ""#notesFile#"" #prereleaseFlag( arguments.version )# ""#zipPath#"" ""#shaPath#"""
		);
		if ( result.exitCode != 0 ) {
			return error(
				"GitHub Release failed (#result.output#). The tag is already pushed; create the release by hand:" & chr( 10 )
				& "  gh release create #tagName# --title #tagName# --notes-file .tmp/release-notes.md #prereleaseFlag( arguments.version )# ""#zipPath#"" ""#shaPath#"""
			);
		}

		print
			.line()
			.boldGreenLine( "Released #tagName#: ForgeBox published, tag pushed, GitHub Release created." )
			.toConsole();
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * Run a native OS command and hand back its exit code and text output, without ever
	 * throwing. Callers decide what a non-zero exit means: for most steps it is a failure, but
	 * for probes like `git rev-parse --verify` it is the expected answer.
	 *
	 * The first word of the command is swapped for a quoted absolute path via findBinary(),
	 * because on some Windows setups the cmd.exe that CommandBox spawns cannot resolve bare
	 * names from PATH at all ('git' is not recognized...), while absolute paths work fine.
	 *
	 * @cmd The full native command line, e.g. "git status --porcelain"
	 */
	private struct function execNative( required string cmd ){
		var binary  = listFirst( arguments.cmd, " " );
		var rest    = listRest( arguments.cmd, " " );
		var fullCmd = findBinary( binary ) & ( len( rest ) ? " " & rest : "" );

		var output = "";
		var failed = false;
		try {
			output = command( "run" ).params( fullCmd ).run( returnOutput = true );
		} catch ( any e ) {
			// The Command DSL throws when the command exits non-zero; the message usually
			// carries the command's own stderr, which is what the caller wants to show.
			failed = true;
			output = e.message & ( len( e.detail ?: "" ) ? " " & e.detail : "" );
		}
		var exitCode = val( shell.getExitCode() );
		if ( failed && exitCode == 0 ) {
			exitCode = 1;
		}
		return { exitCode : exitCode, output : trim( output ) };
	}

	/**
	 * Find a binary on the JVM's own PATH and return it as a quoted absolute path, e.g.
	 * "C:\Program Files\Git\cmd\git.exe". Falls back to the bare name when nothing is found,
	 * which lets the shell try its own lookup (and produces a readable 'not recognized' error
	 * when the tool genuinely is not installed, e.g. gh). Results are cached per task run.
	 *
	 * @name The bare binary name, e.g. "git", "gh"
	 */
	private string function findBinary( required string name ){
		if ( !structKeyExists( variables, "binaryCache" ) ) {
			variables.binaryCache = {};
		}
		if ( structKeyExists( variables.binaryCache, arguments.name ) ) {
			return variables.binaryCache[ arguments.name ];
		}

		var jFile    = createObject( "java", "java.io.File" );
		var pathEnv  = createObject( "java", "java.lang.System" ).getenv( "PATH" );
		var resolved = arguments.name;
		if ( !isNull( pathEnv ) ) {
			for ( var dir in listToArray( pathEnv, jFile.pathSeparator ) ) {
				// The empty extension covers Linux/Mac; the others are the Windows launchers.
				for ( var ext in [ "", ".exe", ".cmd", ".bat" ] ) {
					var candidate = dir & jFile.separator & arguments.name & ext;
					if ( fileExists( candidate ) ) {
						resolved = '"' & candidate & '"';
						break;
					}
				}
				if ( resolved != arguments.name ) {
					break;
				}
			}
		}

		variables.binaryCache[ arguments.name ] = resolved;
		return resolved;
	}

	/**
	 * Pull one version's section out of changelog.md: everything between its `## [version]`
	 * heading and the next `##` heading (or the link-reference block at the bottom). Aborts
	 * with instructions when the section is missing, which is how preflight forces a changelog
	 * entry to exist before a release can ship.
	 *
	 * @version The version whose section to extract, e.g. 1.0.0
	 */
	private string function extractChangelogSection( required string version ){
		var changelogPath = repoPath( "changelog.md" );
		if ( !fileExists( changelogPath ) ) {
			return error( "changelog.md not found at the repo root. Create it before releasing." );
		}

		var lines     = listToArray( fileRead( changelogPath ), chr( 10 ), true );
		var collected = [];
		var inSection = false;
		for ( var rawLine in lines ) {
			var line = reReplace( rawLine, chr( 13 ) & "$", "" );
			// A version heading looks like "## [1.0.0] - 2026-07-24". Matching the literal
			// "[version]" (instead of interpolating the version into a regex) sidesteps escaping
			// the dots, and the closing bracket keeps 1.0.0 from matching 1.0.0-beta.1.
			// ####: a # in a CFML string must be doubled, so this is the two-hash "## " heading level.
			var isHeading = reFind( "^####\s*\[", line );
			if ( !inSection && isHeading && line contains "[#arguments.version#]" ) {
				inSection = true;
				continue;
			}
			if ( inSection ) {
				// The next version heading (or anything at ## level) ends the section. The
				// link-reference lines at the bottom ("[1.0.0]: https://...") never start with
				// ##, but they only appear after the last section, so a lone "[" line ends it too.
				if ( reFind( "^####\s", line ) || reFind( "^\[.+\]:\s*http", line ) ) {
					break;
				}
				collected.append( line );
			}
		}

		if ( !inSection ) {
			return error(
				"changelog.md has no ""## [#arguments.version#]"" section. Move your notes out of "
				& "[Unreleased] into a dated ""## [#arguments.version#] - YYYY-MM-DD"" section, then re-run."
			);
		}

		var notes = trim( arrayToList( collected, chr( 10 ) ) );
		if ( !len( notes ) ) {
			return error( "The ""## [#arguments.version#]"" section in changelog.md is empty. Write the release notes first." );
		}
		return notes;
	}

	/**
	 * A version with a hyphen (1.0.0-beta.4, 2.0.0-rc.1) is a pre-release by semver, so the
	 * GitHub Release gets flagged as one. Returns the flag or an empty string.
	 *
	 * @version The version being released
	 */
	private string function prereleaseFlag( required string version ){
		return find( "-", arguments.version ) ? "--prerelease" : "";
	}

	/**
	 * Turn a repo-root-relative path into an absolute one, anchored on this file's own location
	 * (build/Release.cfc → the repo root is one level up).
	 *
	 * Naming trap: this method must NOT be called resolvePath. CommandBox's BaseTask already has
	 * a resolvePath() and its mixin wins over one declared here, silently — and the built-in
	 * resolves against the TASK FILE's folder, so resolvePath( "box.json" ) hands back
	 * build/box.json with no hint your own function never ran.
	 *
	 * @relative Path relative to the repo root, e.g. "changelog.md"
	 */
	private string function repoPath( required string relative ){
		var buildDir = getDirectoryFromPath( getCurrentTemplatePath() );
		return reReplace( buildDir, "[\\/]build[\\/]?$", "" ) & "/" & arguments.relative;
	}
}
