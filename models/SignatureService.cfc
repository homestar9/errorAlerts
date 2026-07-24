/**
 * SignatureService
 *
 * Creates a repeatable signature that groups matching log events.
 */
component singleton accessors="true" {

	// WireBox injects the module settings.
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";

	/**
	 * compute
	 *
	 * Hashes the category, first 200 message characters, and top stack frame.
	 * A hash collision would group two errors in the same throttle window.
	 *
	 * @logEvent The LogBox LogEvent to fingerprint.
	 */
	string function compute( required any logEvent ){
		var parts = [
			arguments.logEvent.getCategory(),
			normalize( arguments.logEvent.getMessage().left( 200 ) ),
			topFrame( arguments.logEvent.getExtraInfo() )
		];
		return hash( parts.toList( "|" ), "MD5" ).lcase();
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
