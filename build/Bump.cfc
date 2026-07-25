/**
 * Version bump helper: box run-script bump:patch | bump:minor | bump:major
 *
 * Does two things, so cutting a release is one command instead of hand-editing:
 *   1. Bumps the version in box.json (major/minor/patch, standard SemVer).
 *   2. Moves everything under the changelog's "## [Unreleased]" section into a new dated
 *      "## [<new version>] - YYYY-MM-DD" section, and leaves a fresh empty [Unreleased].
 *
 * It does NOT commit, tag, or publish - it only edits the two files, so you review the diff
 * and commit yourself ("git commit -am 'Release x.y.z'"). The real release gates (clean tree,
 * on main, tag unused, gh logged in) live in build/Release.cfc preflight and run at publish time.
 *
 * First release trick: box.json is already 1.0.0 and you want to ship 1.0.0, not 1.0.1. Run
 * "box task run taskFile=build/Bump.cfc :level=none" - it dates the [Unreleased] notes as the
 * CURRENT version without changing box.json.
 */
component {

	/**
	 * Run the bump.
	 *
	 * @level How much to bump: major, minor, patch, or none (date the current version as-is).
	 */
	function run( string level = "patch" ){
		var lvl = lCase( trim( arguments.level ) );
		if ( !listFindNoCase( "major,minor,patch,none", lvl ) ) {
			return error( "Unknown level '#arguments.level#'. Use one of: major, minor, patch, none." );
		}

		var current    = getCurrentVersion();
		var newVersion = ( lvl == "none" ) ? current : nextVersion( current, lvl );
		var today      = dateFormat( now(), "yyyy-mm-dd" );

		// Validate + build the new changelog BEFORE writing anything, so a missing or empty
		// [Unreleased] section aborts without half-editing (box.json bumped, changelog not).
		var newChangelog = buildChangelog( newVersion, today );

		if ( newVersion != current ) {
			setBoxVersion( newVersion );
			print.greenLine( "box.json version: #current# -> #newVersion#" ).toConsole();
		} else {
			print.greenLine( "box.json version stays #current# (level=none)." ).toConsole();
		}

		fileWrite( repoPath( "changelog.md" ), newChangelog );
		print.greenLine( "changelog.md: moved [Unreleased] notes into #### [#newVersion#] - #today#." ).toConsole();

		print
			.line()
			.boldMagentaLine( "Bumped to #newVersion#. Next steps:" )
			.line( "  1. Review the diff:   git diff box.json changelog.md" )
			.line( "  2. Commit:            git commit -am ""Release #newVersion#""" )
			.line( "  3. (Optional) sweep:  box run-script test:release" )
			.line( "  4. Start a server:    box run-script start:2023" )
			.line( "  5. Publish:           box run-script publish:release" )
			.toConsole();
	}

	/********************************************* PRIVATE HELPERS *********************************************/

	/**
	 * Read the current version straight from box.json.
	 */
	private string function getCurrentVersion(){
		var box = deserializeJSON( fileRead( repoPath( "box.json" ) ) );
		return box.version;
	}

	/**
	 * Compute the next version for a major/minor/patch bump. Any pre-release or build suffix
	 * (the part after "-" or "+") is dropped, because a bump produces a clean release version.
	 *
	 * @current The current version, e.g. 1.0.0
	 * @level   major, minor, or patch
	 */
	private string function nextVersion( required string current, required string level ){
		// listFirst with both "-" and "+" as delimiters strips "-beta.1" and "+build" suffixes.
		var core  = listFirst( arguments.current, "-+" );
		var parts = listToArray( core, "." );
		var major = val( parts[ 1 ] ?: "0" );
		var minor = val( parts[ 2 ] ?: "0" );
		var patch = val( parts[ 3 ] ?: "0" );

		switch ( arguments.level ) {
			case "major":
				major++;
				minor = 0;
				patch = 0;
				break;
			case "minor":
				minor++;
				patch = 0;
				break;
			default: // patch
				patch++;
		}
		return "#major#.#minor#.#patch#";
	}

	/**
	 * Write the new version back into box.json with a targeted replace of just the version value,
	 * so the file's existing formatting is left untouched (a full re-serialize would reflow it).
	 *
	 * @version The new version to write
	 */
	private function setBoxVersion( required string version ){
		var boxPath = repoPath( "box.json" );
		var raw     = fileRead( boxPath );

		// Find the first "version":"..." (the package version at the top of box.json). Group 3 is
		// the value between the quotes. We splice just that span rather than using a reReplace
		// backreference: "\1" sitting against a version that starts with a digit gets read as
		// backreference \11 and eats characters.
		var m = reFind( '("version"\s*:\s*")([^"]*)(")', raw, 1, true );
		if ( !arrayLen( m.pos ) || m.pos[ 1 ] == 0 ) {
			return error( "Could not find a ""version"" key to update in box.json." );
		}
		var valStart = m.pos[ 3 ];
		var valLen   = m.len[ 3 ];
		var updated  = left( raw, valStart - 1 ) & arguments.version & mid( raw, valStart + valLen, len( raw ) );
		fileWrite( boxPath, updated );
	}

	/**
	 * Build the whole changelog with the [Unreleased] notes moved into a new dated section for
	 * this version. Aborts if there is no [Unreleased] section, or it has no real content, so a
	 * release can never be cut with empty notes.
	 *
	 * CFML hash trap: "##" in a string is one literal "#". So the regexes below use "####" to
	 * match a two-hash "## " markdown heading, and "#### [" builds the "## [" heading text.
	 *
	 * @version The version to stamp the section with
	 * @date    Today's date, YYYY-MM-DD
	 */
	private string function buildChangelog( required string version, required string date ){
		var path = repoPath( "changelog.md" );
		if ( !fileExists( path ) ) {
			return error( "changelog.md not found at the repo root." );
		}

		var raw   = fileRead( path );
		// Remember whether the file used Windows line endings, so the rewrite keeps the same style.
		var crlf  = ( raw contains ( chr( 13 ) & chr( 10 ) ) );
		var lf    = chr( 10 );
		var lines = listToArray( replace( raw, chr( 13 ) & lf, lf, "all" ), lf, true );

		// Find the "## [Unreleased]" heading.
		var unreleasedIdx = 0;
		for ( var i = 1; i <= arrayLen( lines ); i++ ) {
			if ( reFindNoCase( "^####\s*\[Unreleased\]", lines[ i ] ) ) {
				unreleasedIdx = i;
				break;
			}
		}
		if ( unreleasedIdx == 0 ) {
			return error(
				"changelog.md has no ""## [Unreleased]"" section. Add one and put your notes under it, "
				& "then re-run. (See RELEASE.md for the changelog model.)"
			);
		}

		// The section body runs until the next "## " heading or the link-reference block at the bottom.
		var endIdx = arrayLen( lines ) + 1;
		for ( var i = unreleasedIdx + 1; i <= arrayLen( lines ); i++ ) {
			if ( reFind( "^####\s", lines[ i ] ) || reFind( "^\[.+\]:\s*http", lines[ i ] ) ) {
				endIdx = i;
				break;
			}
		}

		// Collect the body and trim blank lines off both ends.
		var body = [];
		for ( var i = unreleasedIdx + 1; i <= endIdx - 1; i++ ) {
			body.append( lines[ i ] );
		}
		while ( body.len() && !len( trim( body[ 1 ] ) ) ) {
			body.deleteAt( 1 );
		}
		while ( body.len() && !len( trim( body[ body.len() ] ) ) ) {
			body.deleteAt( body.len() );
		}
		if ( !body.len() ) {
			return error( "The ""## [Unreleased]"" section is empty. Write the release notes there first." );
		}

		// Rebuild: keep everything up to and including the (now empty) Unreleased heading, then the
		// new dated section with the moved notes, then whatever followed the old body.
		var out = [];
		for ( var i = 1; i <= unreleasedIdx; i++ ) {
			out.append( lines[ i ] );
		}
		out.append( "" );
		out.append( "#### [" & arguments.version & "] - " & arguments.date );
		out.append( "" );
		for ( var b in body ) {
			out.append( b );
		}
		out.append( "" );
		for ( var i = endIdx; i <= arrayLen( lines ); i++ ) {
			out.append( lines[ i ] );
		}

		return arrayToList( out, crlf ? ( chr( 13 ) & lf ) : lf );
	}

	/**
	 * Turn a repo-root-relative path into an absolute one, anchored on this file's own location
	 * (build/Bump.cfc -> the repo root is one level up). Named repoPath, not resolvePath, because
	 * CommandBox's BaseTask already has a resolvePath() whose mixin would silently win.
	 *
	 * @relative Path relative to the repo root, e.g. "box.json"
	 */
	private string function repoPath( required string relative ){
		var buildDir = getDirectoryFromPath( getCurrentTemplatePath() );
		return reReplace( buildDir, "[\\/]build[\\/]?$", "" ) & "/" & arguments.relative;
	}
}
