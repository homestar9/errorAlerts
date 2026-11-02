/**
 * GuardedPayloadBuilder
 *
 * A PayloadBuilder whose toJson() refuses to serialize a function or an object.
 *
 * On Adobe, serializeJSON() on a function or a non-CFC Java object can walk its
 * bean properties forever. A spec that let one reach the real serializer would
 * hang the whole TestBox run instead of failing. This override counts the
 * value and returns a placeholder, so the spec fails at once on every engine.
 *
 * Do not replace this with a MockBox $() stub on toJson(). MockBox's
 * normalizeArguments() falls back to serializeJSON() on the arguments, which
 * would hang before the stub's callback ran.
 */
component extends="errorAlerts.models.PayloadBuilder" {

	/**
	 * init
	 *
	 * Starts the hit counter, then runs the parent's init().
	 */
	function init(){
		super.init();
		variables.guardHits = 0;
		return this;
	}

	/**
	 * getGuardHits
	 *
	 * Returns how many toJson() calls received a value the walk must never emit.
	 */
	numeric function getGuardHits(){
		return variables.guardHits;
	}

	/**
	 * toJson
	 *
	 * Serializes the value only when it holds nothing but data the walk builds.
	 * Otherwise counts a hit and returns a placeholder string.
	 *
	 * @value The value to serialize, any type.
	 */
	private string function toJson( required any value ){
		if ( !isSafe( arguments.value, 0 ) ) {
			variables.guardHits++;
			return super.toJson( "[guard: unsafe value]" );
		}
		return super.toJson( arguments.value );
	}

	/**
	 * isSafe
	 *
	 * Checks that a value holds only simple values, arrays, plain structs and
	 * queries. Never reads a property of a function or an object.
	 *
	 * @value The value to check, any type, may be null.
	 * @depth The current nesting level. The walk itself stops at 5.
	 */
	private boolean function isSafe( any value, required numeric depth ){
		if ( isNull( arguments.value ) || isSimpleValue( arguments.value ) ) {
			return true;
		}
		if ( isCustomFunction( arguments.value ) ) {
			return false;
		}
		if ( isQuery( arguments.value ) ) {
			return true;
		}
		// The walk turns XML into its markup, so XML here means it skipped that step. Check it
		// before arrays and structs: BoxLang reports a document as an array, Lucee as a struct.
		if ( isXmlNode( arguments.value ) ) {
			return false;
		}
		if ( isObject( arguments.value ) || arguments.depth > 20 ) {
			return false;
		}
		if ( isArray( arguments.value ) ) {
			for ( var i = 1; i <= arguments.value.len(); i++ ) {
				if ( arrayIsDefined( arguments.value, i ) && !isSafe( arguments.value[ i ], arguments.depth + 1 ) ) {
					return false;
				}
			}
			return true;
		}
		if ( isStruct( arguments.value ) ) {
			for ( var key in arguments.value ) {
				if ( !isNull( arguments.value[ key ] ) && !isSafe( arguments.value[ key ], arguments.depth + 1 ) ) {
					return false;
				}
			}
			return true;
		}
		return false;
	}

}
