/**
 * SignatureService
 *
 * Computes a stable fingerprint for a log event so the throttle can recognize
 * "the same error happening again". Pure logic, no side effects.
 */
component singleton accessors="true" {

	// Injected properties
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";

	/**
	 * Computes the signature: an MD5 hash of the category, the normalized first
	 * 200 characters of the message, and the top stack frame (when the event
	 * carries an exception). MD5 is plenty here; collisions only risk merging
	 * two errors into one throttle bucket, and it hashes identically on Adobe
	 * CF and BoxLang.
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
	 * Returns "template:line" for the first tagContext frame when extraInfo is
	 * an exception (a cfcatch struct carries tagContext), else "". Including
	 * the throw site keeps two different errors with the same message text in
	 * separate throttle buckets.
	 *
	 * @extraInfo The log event's extraInfo value, any type.
	 */
	private string function topFrame( required any extraInfo ){
		// cfcatch objects are struct-like but not true structs on Adobe CF,
		// so this mirrors LogEvent.getExtraInfoAsString()'s detection style.
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
	 * Collapses digit runs to "{n}" and UUIDs to "{uuid}" (when
	 * settings.normalizeSignatures is on) so messages that differ only by ids,
	 * like "Order 123 failed" vs "Order 456 failed", produce one signature.
	 *
	 * @message The message fragment to normalize.
	 */
	private string function normalize( required string message ){
		if ( !settings.normalizeSignatures ) {
			return arguments.message;
		}

		// Standard UUIDs (8-4-4-4-12), then CFML createUUID() format (8-4-4-16).
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
