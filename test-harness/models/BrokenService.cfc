/**
 * BrokenService
 *
 * Fails in its constructor, so WireBox throws while building it. The resulting
 * alert shows a stack full of WireBox frames rather than application code.
 */
component singleton {

	/**
	 * init
	 *
	 * Always throws.
	 */
	function init(){
		throw(
			type    = "Harness.Wirebox.BadConstructor",
			message = "BrokenService cannot be constructed",
			detail  = "Its init() always throws so WireBox object creation failures can be tested."
		);
	}

}
