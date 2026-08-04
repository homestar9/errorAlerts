/**
 * FrameClassifier
 *
 * Decides whether a stack frame belongs to the application or to framework
 * code, using the settings.applicationFramePrefixes list. PayloadBuilder uses
 * it to pin the first application-owned frame in the email, and
 * SignatureService uses the same frame when grouping errors.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";
	property name="coldbox"  inject="coldbox";

	/**
	 * appRelativePath
	 *
	 * Returns the path relative to the application root, starting with "/",
	 * with backslashes normalized to forward slashes. Returns an empty string
	 * for a path outside the application root, or when the root is unknown.
	 *
	 * This always strips the root, unlike PayloadBuilder.relativeTemplate(),
	 * which obeys the settings.relativePaths display setting. Classification
	 * must work the same no matter how paths are displayed.
	 *
	 * @template The absolute file path from a stack frame.
	 */
	string function appRelativePath( required string template ){
		try {
			var root = coldbox.getAppRootPath().replace( "\", "/", "all" );
			var path = arguments.template.replace( "\", "/", "all" );

			if ( root.len() && path.len() && path.findNoCase( root ) == 1 ) {
				return "/" & path.removeChars( 1, root.len() );
			}
		} catch ( any e ) {
		}

		return "";
	}

	/**
	 * isApplicationFrame
	 *
	 * Checks whether a template path starts with one of the configured
	 * application prefixes, ignoring case. Framework paths and paths outside
	 * the application root return false.
	 *
	 * @template The absolute file path from a stack frame.
	 */
	boolean function isApplicationFrame( required string template ){
		var relative = appRelativePath( arguments.template );

		if ( !relative.len() ) {
			return false;
		}

		for ( var prefix in settings.applicationFramePrefixes ) {
			if ( relative.findNoCase( prefix ) == 1 ) {
				return true;
			}
		}

		return false;
	}

	/**
	 * findFirstApplicationFrame
	 *
	 * Scans a raw tagContext array for the first application-owned frame.
	 * Returns { index, template, line } with the raw template path, or an
	 * empty struct when no frame qualifies within maxScan frames.
	 *
	 * Driver frames like "|SQLServer|6.0|" can never match a prefix, so no
	 * separate skip rule is needed here.
	 *
	 * @tagContext The raw tagContext array from the exception.
	 * @maxScan    How many frames to inspect before giving up.
	 */
	struct function findFirstApplicationFrame( required array tagContext, numeric maxScan = 100 ){
		var limit = min( arguments.tagContext.len(), arguments.maxScan );

		for ( var i = 1; i <= limit; i++ ) {
			var frame    = arguments.tagContext[ i ];
			var template = structKeyExists( frame, "template" ) ? toString( frame.template ) : "";

			if ( template.len() && isApplicationFrame( template ) ) {
				return {
					index    : i,
					template : template,
					line     : structKeyExists( frame, "line" ) ? val( frame.line ) : 0
				};
			}
		}

		return {};
	}

}
