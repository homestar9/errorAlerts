/**
 * ThrottleService
 *
 * Tracks how often each error signature fires and decides SEND vs SUPPRESS.
 * Semantics: a FIXED window anchored at the signature's first occurrence. The
 * first `maxPerWindow` occurrences send immediately; the rest are counted. When
 * the window expires (rolled by the next occurrence, or swept by the scheduled
 * flush), any suppressed count becomes one digest seed.
 *
 * State is an in-memory struct, per JVM by design: counters reset on restart or
 * fwreinit, and a pending digest is lost with them. On a web farm each instance
 * throttles independently, so N is effectively multiplied by instance count.
 */
component singleton accessors="true" {

	// Injected properties
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";

	/**
	 * Constructor. Sets up the empty window registry and the System handle
	 * used for stderr notes (this module never logs through LogBox).
	 */
	function init(){
		variables.windows = {};
		variables.system  = createObject( "java", "java.lang.System" );
		return this;
	}

	/**
	 * Records one occurrence of a signature and returns the verdict:
	 *   {
	 *     action        : "SEND" | "SUPPRESS",
	 *     occurrence    : n,   // position within the current window
	 *     expiredDigest : {}   // digest seed when THIS call rolled over an
	 *   }                      // expired window that had suppressions
	 *
	 * All struct work happens inside ONE named exclusive lock; the operations
	 * are microseconds, so a single coarse lock is both correct and simple.
	 * On lock timeout it fails OPEN and returns SEND: a rare duplicate email
	 * beats a silently dropped alert.
	 *
	 * @signature The error signature from SignatureService.
	 * @snapshot  A compact struct describing this occurrence, kept for digests.
	 */
	struct function record( required string signature, required struct snapshot ){
		var result = { action : "SEND", occurrence : 1, expiredDigest : {} };
		var nowMs  = getTickCount();

		try {
			lock name="errorAlerts-throttle" type="exclusive" timeout="5" throwOnTimeout="true" {
				// Roll an expired window first; its suppressions become the digest seed.
				if (
					variables.windows.keyExists( arguments.signature )
					&& nowMs >= variables.windows[ arguments.signature ].windowStart + settings.throttle.windowSeconds * 1000
				) {
					if ( variables.windows[ arguments.signature ].suppressedCount > 0 ) {
						result.expiredDigest = buildSeed( arguments.signature, variables.windows[ arguments.signature ] );
					}
					variables.windows.delete( arguments.signature );
				}

				// First occurrence in a window: open it and send.
				if ( !variables.windows.keyExists( arguments.signature ) ) {
					if ( variables.windows.count() >= settings.throttle.maxTrackedSignatures ) {
						evictExpired( nowMs );
					}
					if ( variables.windows.count() >= settings.throttle.maxTrackedSignatures ) {
						// Fail open: send the alert but track nothing, so a flood of
						// unique signatures cannot grow memory without bound.
						variables.system.err.println(
							"errorAlerts throttle is tracking #settings.throttle.maxTrackedSignatures# signatures; sending untracked."
						);
						return result;
					}
					variables.windows[ arguments.signature ] = {
						windowStart     : nowMs,
						sentCount       : 1,
						totalCount      : 1,
						suppressedCount : 0,
						firstSeen       : now(),
						lastSeen        : now(),
						lastEvent       : arguments.snapshot
					};
					return result;
				}

				// A live window: count the occurrence, send only below the cap.
				var entry = variables.windows[ arguments.signature ];
				entry.totalCount++;
				entry.lastSeen    = now();
				entry.lastEvent   = arguments.snapshot;
				result.occurrence = entry.totalCount;
				if ( entry.sentCount < settings.throttle.maxPerWindow ) {
					entry.sentCount++;
				} else {
					entry.suppressedCount++;
					result.action = "SUPPRESS";
				}
			}
		} catch ( any e ) {
			// Fail OPEN (verdict stays SEND): a duplicate beats a dropped alert.
			variables.system.err.println( "errorAlerts throttle failed open: #e.message#" );
		}

		return result;
	}

	/**
	 * Sweeps ALL expired windows and returns an array of digest seeds for the
	 * ones that suppressed anything. Every expired window is deleted either
	 * way. The scheduled task calls this so digests are never stranded when
	 * traffic stops after a burst.
	 */
	array function flushExpired(){
		var seeds = [];
		var nowMs = getTickCount();

		try {
			lock name="errorAlerts-throttle" type="exclusive" timeout="5" throwOnTimeout="true" {
				// Iterate a key copy so deleting entries mid-loop is safe.
				for ( var signature in variables.windows.keyArray() ) {
					var entry = variables.windows[ signature ];
					if ( nowMs >= entry.windowStart + settings.throttle.windowSeconds * 1000 ) {
						if ( entry.suppressedCount > 0 ) {
							seeds.append( buildSeed( signature, entry ) );
						}
						variables.windows.delete( signature );
					}
				}
			}
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts digest flush failed: #e.message#" );
		}

		return seeds;
	}

	/**
	 * Clears all throttle state. Used by tests and available to hosts that want
	 * a clean slate (e.g. after changing throttle settings at runtime).
	 */
	void function reset(){
		lock name="errorAlerts-throttle" type="exclusive" timeout="5" {
			variables.windows = {};
		}
	}

	/**
	 * Deletes every expired window without collecting digests. Only called when
	 * the registry hits maxTrackedSignatures, so losing a rare digest at the
	 * cap is accepted in exchange for bounded memory.
	 *
	 * @nowMs The current tick count, passed in so record() and this agree on "now".
	 */
	private void function evictExpired( required numeric nowMs ){
		for ( var signature in variables.windows.keyArray() ) {
			if ( arguments.nowMs >= variables.windows[ signature ].windowStart + settings.throttle.windowSeconds * 1000 ) {
				variables.windows.delete( signature );
			}
		}
	}

	/**
	 * Builds the digest seed for an expired window: everything PayloadBuilder
	 * needs to describe the burst without holding onto the window itself.
	 *
	 * @signature The error signature the window belongs to.
	 * @entry     The window entry being retired.
	 */
	private struct function buildSeed( required string signature, required struct entry ){
		return {
			signature       : arguments.signature,
			message         : arguments.entry.lastEvent.message,
			category        : arguments.entry.lastEvent.category,
			severity        : arguments.entry.lastEvent.severity,
			totalCount      : arguments.entry.totalCount,
			sentCount       : arguments.entry.sentCount,
			suppressedCount : arguments.entry.suppressedCount,
			firstSeen       : arguments.entry.firstSeen,
			lastSeen        : arguments.entry.lastSeen,
			windowSeconds   : settings.throttle.windowSeconds
		};
	}

}
