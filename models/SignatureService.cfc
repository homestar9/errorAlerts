/**
 * SignatureService
 *
 * Creates a repeatable signature that groups matching log events.
 */
component singleton accessors="true" {

	// WireBox injects these dependencies.
	property name="settings"        inject="coldbox:moduleSettings:errorAlerts";
	property name="frameClassifier" inject="FrameClassifier@errorAlerts";

	/**
	 * compute
	 *
	 * Hashes the category, first 200 message characters, the top stack frame,
	 * and the first application-owned stack frame. A hash collision would
	 * group two errors in the same throttle window.
	 *
	 * The application frame matters most for database errors: their top frame
	 * is always the same framework grammar file, so without the application
	 * frame two unrelated failing queries would only differ by message text.
	 * The top frame stays in the hash so one call site that fails two
	 * different ways still produces two signatures.
	 *
	 * @logEvent The LogBox LogEvent to fingerprint.
	 */
	string function compute( required any logEvent ){
		var parts = [
			arguments.logEvent.getCategory(),
			normalize( arguments.logEvent.getMessage().left( 200 ) ),
			topFrame( arguments.logEvent.getExtraInfo() ),
			applicationFrame( arguments.logEvent.getExtraInfo() )
		];
		return hash( parts.toList( "|" ), "MD5" ).lcase();
	}

	/**
	 * applicationFrame
	 *
	 * Returns "template:line" for the first application-owned exception frame,
	 * using the raw absolute path so display settings cannot change the hash.
	 * Returns an empty string when no frame qualifies or on any failure.
	 *
	 * @extraInfo The log event's extraInfo value, any type.
	 */
	private string function applicationFrame( required any extraInfo ){
		try {
			if (
				( isObject( arguments.extraInfo ) || isStruct( arguments.extraInfo ) )
				&& structKeyExists( arguments.extraInfo, "tagContext" )
				&& isArray( arguments.extraInfo.tagContext )
				&& arguments.extraInfo.tagContext.len()
			) {
				var found = frameClassifier.findFirstApplicationFrame( arguments.extraInfo.tagContext );
				if ( !found.isEmpty() ) {
					return "#found.template#:#found.line#";
				}
			}
		} catch ( any e ) {
		}
		return "";
	}

	/**
	 * topFrame
	 *
	 * Returns "template:line" for the first exception frame.
	 * Returns an empty string when the event has no exception frame.
	 *
	 * @extraInfo The log event's extraInfo value, any type.
	 */
	private string function topFrame( required any extraInfo ){
		// Adobe ColdFusion cfcatch values can be objects instead of structs.
		// Check for either form before reading tagContext.
		if (
			( isObject( arguments.extraInfo ) || isStruct( arguments.extraInfo ) )
			&& structKeyExists( arguments.extraInfo, "tagContext" )
			&& isArray( arguments.extraInfo.tagContext )
			&& arguments.extraInfo.tagContext.len()
		) {
			var frame    = arguments.extraInfo.tagContext[ 1 ];
			var template = structKeyExists( frame, "template" ) ? frame.template : "";
			var line     = structKeyExists( frame, "line" ) ? frame.line : 0;
			return "#template#:#line#";
		}
		return "";
	}

	/**
	 * normalize
	 *
	 * Replaces UUIDs and digit runs when signature normalization is enabled.
	 *
	 * @message The message fragment to normalize.
	 */
	private string function normalize( required string message ){
		if ( !settings.normalizeSignatures ) {
			return arguments.message;
		}

		// Replace standard UUIDs before the shorter CFML createUUID() form.
		var result = arguments.message.reReplaceNoCase(
			"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
			"{uuid}",
			"all"
		);
		result = result.reReplaceNoCase(
			"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{16}",
			"{uuid}",
			"all"
		);
		return result.reReplace( "[0-9]+", "{n}", "all" );
	}

}
