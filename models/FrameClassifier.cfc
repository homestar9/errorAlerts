/**
 * FrameClassifier
 *
 * Uses settings.applicationFramePrefixes to identify application stack frames.
 * PayloadBuilder shows the first matching frame in the email. SignatureService
 * uses the same frame when it groups errors.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";
	property name="coldbox"  inject="coldbox";

	/**
	 * appRelativePath
	 *
	 * Returns a stack-frame path relative to the application root.
	 * The result starts with "/" and uses forward slashes. A path outside the
	 * application root returns an empty string.
	 *
	 * This method always removes the root. PayloadBuilder.relativeTemplate()
	 * follows the relativePaths display setting instead. Display settings must
	 * not change frame classification.
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
	 * Finds the first application frame in a raw tagContext array.
	 * Returns its index, template, and line. Returns an empty struct if the first
	 * maxScan frames contain no match.
	 *
	 * Database driver frames cannot match an application path prefix.
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
