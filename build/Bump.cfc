/**
 * Raises the version and dates the changelog.
 *
 * Run it with: box run-script bump:patch (or bump:minor, bump:major)
 *
 * It prepares two release changes:
 *   1. Raises the version in box.json.
 *   2. Moves the Unreleased notes into a dated section for the new version.
 *
 * It does not commit, tag, or publish. Review and commit the changes yourself.
 *
 * For a first release, use :level=none when box.json already has the version to
 * publish. This dates the notes without changing the version.
 */
component {

	/**
	 * init
	 *
	 * Loads the settings.
	 */
	function init(){
		variables.config = new BuildConfig( getDirectoryFromPath( getCurrentTemplatePath() ) );
		variables.s      = variables.config.getSettings();
		return this;
	}

	/**
	 * run
	 *
	 * Raises the version and moves the changelog notes.
	 *
	 * @level  How much to raise. See the list in nextVersion(), or run with an unknown level to
	 *         have them printed.
	 * @preid  The prerelease label to use, such as beta or alpha. Only used by the pre levels.
	 *         Defaults to beta when starting a prerelease.
	 * @dryRun Show what would change without writing anything.
	 */
	function run( string level = "patch", string preid = "", boolean dryRun = false ){
		var lvl = lCase( trim( arguments.level ) );
		if ( !listFindNoCase( levels(), lvl ) ) {
			return fail(
				"Unknown level '#arguments.level#'.",
				[
					"major, minor, patch            raise the version. On a prerelease these settle on",
					"                               the version it was leading up to.",
					"prerelease                     step a prerelease forward, beta.3 to beta.4.",
					"premajor, preminor, prepatch   start a prerelease, :preid=beta by default.",
					"none                           keep the version and just date the changelog."
				],
				"The levels you can use"
			);
		}

		var current    = variables.config.version();
		var newVersion = ( lvl == "none" ) ? current : nextVersion( current, lvl, trim( arguments.preid ) );
		var today      = dateFormat( now(), "yyyy-mm-dd" );

		// Validate the new changelog before changing box.json.
		var newChangelog = buildChangelog( newVersion, today );

		if ( arguments.dryRun ) {
			print
				.line()
				.boldYellowLine( "Dry run: nothing was written." )
				.line( "Version:   #current# -> #newVersion#" )
				.line( "Changelog: notes would move into #### [#newVersion#] - #today#" )
				.line()
				.boldLine( "The new changelog would start like this:" )
				.line( left( newChangelog, 600 ) )
				.toConsole();
			return;
		}

		if ( newVersion != current ) {
			setBoxVersion( newVersion );
			print.greenLine( "box.json: #current# -> #newVersion#" ).toConsole();
		} else {
			print.greenLine( "box.json stays at #current# (level=none)." ).toConsole();
		}

		fileWrite( variables.config.repoPath( variables.s.changelog ), newChangelog );
		print.greenLine( "#variables.s.changelog#: notes moved into #### [#newVersion#] - #today#" ).toConsole();

		print
			.line()
			.boldMagentaLine( "Now at #newVersion#. Next steps:" )
			.line( "  1. Review:        git diff -- box.json ""#variables.s.changelog#""" )
			.line( "  2. Stage:         git add box.json ""#variables.s.changelog#""" )
			.line( "  3. Check staged:  git diff --staged" )
			.line( "  4. Commit:        git commit -m ""Release #newVersion#""" )
			.line( "  5. Check:         box run-script release:check" )
			.line( "  6. Release:       box run-script release" )
			.toConsole();
	}

	/******************************** Private helpers ********************************/

	/**
	 * fail
	 *
	 * Stops the task, printing guidance that spans several lines.
	 *
	 * CommandBox error() removes line breaks and ends the task. Print detailed
	 * guidance first so its formatting stays readable.
	 *
	 * @summary One line saying what went wrong.
	 * @detail  Lines of guidance to print first.
	 * @heading A short label for the guidance.
	 */
	private function fail( required string summary, array detail = [], string heading = "What to do" ){
		if ( arrayLen( arguments.detail ) ) {
			print.line().boldLine( arguments.heading & ":" ).toConsole();
			for ( var line in arguments.detail ) {
				print.yellowLine( "  " & line ).toConsole();
			}
			print.line().toConsole();
		}
		return error( arguments.summary );
	}

	/**
	 * levels
	 *
	 * The levels run() accepts, as a comma separated list.
	 */
	private string function levels(){
		return "major,minor,patch,prerelease,premajor,preminor,prepatch,none";
	}

	/**
	 * parseVersion
	 *
	 * Splits a version into its parts. For 1.2.3-beta.4+build7 that is major 1, minor 2,
	 * patch 3, prerelease "beta.4", and build "build7".
	 *
	 * @version The version to split.
	 */
	private struct function parseVersion( required string version ){
		var remaining = trim( arguments.version );

		var build = "";
		if ( find( "+", remaining ) ) {
			build     = mid( remaining, find( "+", remaining ) + 1, len( remaining ) );
			remaining = left( remaining, find( "+", remaining ) - 1 );
		}

		var prerelease = "";
		if ( find( "-", remaining ) ) {
			prerelease = mid( remaining, find( "-", remaining ) + 1, len( remaining ) );
			remaining  = left( remaining, find( "-", remaining ) - 1 );
		}

		var parts = listToArray( remaining, "." );
		return {
			"major"      : val( parts[ 1 ] ?: "0" ),
			"minor"      : val( parts[ 2 ] ?: "0" ),
			"patch"      : val( parts[ 3 ] ?: "0" ),
			"prerelease" : prerelease,
			"build"      : build
		};
	}

	/**
	 * nextVersion
	 *
	 * Works out the next version.
	 *
	 * SemVer places 1.1.0-beta.3 before 1.1.0. Finishing a prerelease
	 * returns the version that the prerelease was testing:
	 *
	 *   1.1.0-beta.3  patch       -> 1.1.0        the version the beta was for
	 *   1.1.0-beta.3  minor       -> 1.1.0        same, because the patch part is 0
	 *   2.0.0-beta.3  major       -> 2.0.0        same, because minor and patch are 0
	 *   1.1.2-beta.3  minor       -> 1.2.0        the beta was not for a minor release
	 *   1.1.0         patch       -> 1.1.1        no prerelease, so just step up
	 *   1.1.0-beta.3  prerelease  -> 1.1.0-beta.4
	 *   1.1.0         preminor    -> 1.2.0-beta.1
	 *
	 * @current The current version.
	 * @level   One of the levels listed in levels().
	 * @preid   The prerelease label. Empty means keep the current one, or use beta when starting.
	 */
	private string function nextVersion( required string current, required string level, string preid = "" ){
		var p      = parseVersion( arguments.current );
		var hasPre = len( p.prerelease ) > 0;
		// Starting a prerelease needs a label, so fall back to the common one.
		var label  = len( arguments.preid ) ? arguments.preid : "beta";

		switch ( arguments.level ) {
			case "major":
				// Already a prerelease of this exact major release, so just settle on it.
				if ( hasPre && p.minor == 0 && p.patch == 0 ) {
					return "#p.major#.0.0";
				}
				return "#p.major + 1#.0.0";

			case "minor":
				if ( hasPre && p.patch == 0 ) {
					return "#p.major#.#p.minor#.0";
				}
				return "#p.major#.#p.minor + 1#.0";

			case "patch":
				if ( hasPre ) {
					return "#p.major#.#p.minor#.#p.patch#";
				}
				return "#p.major#.#p.minor#.#p.patch + 1#";

			case "premajor":
				return "#p.major + 1#.0.0-#label#.1";

			case "preminor":
				return "#p.major#.#p.minor + 1#.0-#label#.1";

			case "prepatch":
				return "#p.major#.#p.minor#.#p.patch + 1#-#label#.1";

			case "prerelease":
				return nextPrerelease( p, arguments.preid );
		}

		return arguments.current;
	}

	/**
	 * nextPrerelease
	 *
	 * Advances an existing prerelease number.
	 * beta.3 becomes beta.4. A missing number starts at 1. A new label also
	 * starts at 1.
	 *
	 * @parsed The current version, already split up.
	 * @preid  The wanted label, or empty to keep the current one.
	 */
	private string function nextPrerelease( required struct parsed, string preid = "" ){
		var core = "#arguments.parsed.major#.#arguments.parsed.minor#.#arguments.parsed.patch#";

		if ( !len( arguments.parsed.prerelease ) ) {
			return fail(
				"#core# is not a prerelease, so there is nothing to step forward.",
				[
					"box run-script bump:beta     the next minor release as a beta",
					"box run-script bump:alpha    the same, labelled alpha",
					":level=prepatch              a prerelease of the next patch",
					":level=premajor              a prerelease of the next major"
				],
				"To start a prerelease"
			);
		}

		// Take the trailing number off the label, when there is one.
		var segments = listToArray( arguments.parsed.prerelease, "." );
		var label    = arguments.parsed.prerelease;
		var counter  = 0;
		if ( arrayLen( segments ) > 1 && isNumeric( segments[ arrayLen( segments ) ] ) ) {
			counter = val( segments[ arrayLen( segments ) ] );
			arrayDeleteAt( segments, arrayLen( segments ) );
			label = arrayToList( segments, "." );
		}

		// A new prerelease label starts its own count at 1.
		if ( len( arguments.preid ) && arguments.preid != label ) {
			return "#core#-#arguments.preid#.1";
		}

		return "#core#-#label#.#counter + 1#";
	}

	/**
	 * setBoxVersion
	 *
	 * Replaces only the version value in box.json so formatting stays unchanged.
	 *
	 * @version The new version.
	 */
	private function setBoxVersion( required string version ){
		var boxPath = variables.config.repoPath( "box.json" );
		var raw     = fileRead( boxPath );

		// Splice the value directly so a version digit cannot change a regex group number.
		var m = reFind( '("version"\s*:\s*")([^"]*)(")', raw, 1, true );
		if ( !arrayLen( m.pos ) || m.pos[ 1 ] == 0 ) {
			return error( "Could not find a ""version"" entry in box.json." );
		}
		var valStart = m.pos[ 3 ];
		var valLen   = m.len[ 3 ];
		fileWrite( boxPath, left( raw, valStart - 1 ) & arguments.version & mid( raw, valStart + valLen, len( raw ) ) );
	}

	/**
	 * buildChangelog
	 *
	 * Moves the Unreleased notes into a new dated changelog section.
	 * A missing or empty Unreleased section stops the task.
	 *
	 * CFML uses ## for one literal # inside a string. The patterns use #### to
	 * match the two hashes in a Markdown heading.
	 *
	 * @version The version to date the section with.
	 * @date    Today, as YYYY-MM-DD.
	 */
	private string function buildChangelog( required string version, required string date ){
		var path = variables.config.repoPath( variables.s.changelog );
		if ( !fileExists( path ) ) {
			return error(
				"No #variables.s.changelog# found in the project root. Create one with an ""#### [Unreleased]"" section, "
				& "or run: box task run taskFile=build/Install.cfc"
			);
		}

		var raw   = fileRead( path );
		// Remember the line ending style so the rewrite keeps it.
		var crlf  = ( raw contains ( chr( 13 ) & chr( 10 ) ) );
		var lf    = chr( 10 );
		var lines = listToArray( replace( raw, chr( 13 ) & lf, lf, "all" ), lf, true );

		var unreleasedIdx = 0;
		for ( var i = 1; i <= arrayLen( lines ); i++ ) {
			if ( reFindNoCase( "^####\s*\[Unreleased\]", lines[ i ] ) ) {
				unreleasedIdx = i;
				break;
			}
		}
		if ( unreleasedIdx == 0 ) {
			return error(
				"#variables.s.changelog# has no ""#### [Unreleased]"" section. Add one, put your notes under it, and run this again."
			);
		}

		// The section runs until the next "## " heading, or the link list at the bottom.
		var endIdx = arrayLen( lines ) + 1;
		for ( var i = unreleasedIdx + 1; i <= arrayLen( lines ); i++ ) {
			if ( reFind( "^####\s", lines[ i ] ) || reFind( "^\[.+\]:\s*http", lines[ i ] ) ) {
				endIdx = i;
				break;
			}
		}

		// Take the notes and trim the blank lines off both ends.
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
			return error( "The ""#### [Unreleased]"" section in #variables.s.changelog# is empty. Write the release notes first." );
		}

		// Insert the dated section after the now empty Unreleased heading.
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
}
