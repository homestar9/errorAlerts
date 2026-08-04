/**
 * ThrottleService
 *
 * Counts each error signature during a fixed window. The first
 * `maxPerWindow` occurrences are sent, and later occurrences are included in
 * one digest after the window expires.
 *
 * Counts are stored in memory for one JVM. A restart clears the counts and any
 * pending digest. Each server in a cluster keeps its own counts.
 *
 * BoxLang 1.x did not enforce CFML named locks across cfthread bodies in the
 * concurrency test. ReentrantLock provides the required shared lock on both
 * supported engines.
 */
component singleton accessors="true" {

	// WireBox injects the module settings.
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";

	/**
	 * init
	 *
	 * Creates the window registry, shared lock, and System.err writer.
	 */
	function init(){
		variables.windows = {};
		variables.system  = createObject( "java", "java.lang.System" );
		variables.mutex   = createObject( "java", "java.util.concurrent.locks.ReentrantLock" ).init();
		variables.seconds = createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS;
		return this;
	}

	/**
	 * record
	 *
	 * Records one occurrence and returns this result:
	 *   {
	 *     action        : "SEND" | "SUPPRESS",
	 *     occurrence    : n,
	 *     expiredDigest : {}
	 *   }
	 *
	 * expiredDigest contains a digest when this call closes an expired window.
	 * If the lock cannot be acquired, the method returns SEND so the alert is
	 * not lost.
	 *
	 * @signature The error signature from SignatureService.
	 * @snapshot  A compact struct describing this occurrence, kept for digests.
	 */
	struct function record( required string signature, required struct snapshot ){
		var result = { action : "SEND", occurrence : 1, expiredDigest : {} };
		var nowMs  = getTickCount();

		if ( !acquire() ) {
			return result;
		}

		try {
			// Close an expired window before recording the new occurrence.
			if (
				variables.windows.keyExists( arguments.signature )
				&& nowMs >= variables.windows[ arguments.signature ].windowStart + settings.throttle.windowSeconds * 1000
			) {
				if ( variables.windows[ arguments.signature ].suppressedCount > 0 ) {
					result.expiredDigest = buildSeed( arguments.signature, variables.windows[ arguments.signature ] );
				}
				variables.windows.delete( arguments.signature );
			}

			// Start a window for the first occurrence.
			if ( !variables.windows.keyExists( arguments.signature ) ) {
				if ( variables.windows.count() >= settings.throttle.maxTrackedSignatures ) {
					evictExpired( nowMs );
				}
				if ( variables.windows.count() >= settings.throttle.maxTrackedSignatures ) {
					// Send without tracking when the registry is still full.
					// This keeps memory bounded without dropping the alert.
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
					lastEvent       : arguments.snapshot,
					// Distinct routes and client addresses seen this window,
					// capped at settings.digestSampleSize. The overflow flags
					// say "there were more" once the cap is hit.
					samples         : { route : [], client : [] },
					overflow        : { route : false, client : false }
				};
				addSamples( variables.windows[ arguments.signature ], arguments.snapshot );
				return result;
			}

			// Count the occurrence and suppress it after the send limit.
			var entry = variables.windows[ arguments.signature ];
			entry.totalCount++;
			entry.lastSeen    = now();
			entry.lastEvent   = arguments.snapshot;
			addSamples( entry, arguments.snapshot );
			result.occurrence = entry.totalCount;
			if ( entry.sentCount < settings.throttle.maxPerWindow ) {
				entry.sentCount++;
			} else {
				entry.suppressedCount++;
				result.action = "SUPPRESS";
			}
		} catch ( any e ) {
			// Keep the SEND result so an internal error cannot drop the alert.
			variables.system.err.println( "errorAlerts throttle failed open: #e.message#" );
		} finally {
			variables.mutex.unlock();
		}

		return result;
	}

	/**
	 * flushExpired
	 *
	 * Deletes expired windows and returns digests for those with suppressions.
	 * The scheduled task calls this when no new error closes the window.
	 */
	array function flushExpired(){
		var seeds = [];
		var nowMs = getTickCount();

		if ( !acquire() ) {
			return seeds;
		}

		try {
			// Iterate over copied keys so entries can be deleted during the loop.
			for ( var signature in variables.windows.keyArray() ) {
				var entry = variables.windows[ signature ];
				if ( nowMs >= entry.windowStart + settings.throttle.windowSeconds * 1000 ) {
					if ( entry.suppressedCount > 0 ) {
						seeds.append( buildSeed( signature, entry ) );
					}
					variables.windows.delete( signature );
				}
			}
		} catch ( any e ) {
			variables.system.err.println( "errorAlerts digest flush failed: #e.message#" );
		} finally {
			variables.mutex.unlock();
		}

		return seeds;
	}

	/**
	 * reset
	 *
	 * Clears every throttle window.
	 */
	void function reset(){
		if ( !acquire() ) {
			return;
		}
		try {
			variables.windows = {};
		} finally {
			variables.mutex.unlock();
		}
	}

	/**
	 * acquire
	 *
	 * Waits up to five seconds for the shared lock.
	 * Returns false and writes to System.err when the lock is unavailable.
	 */
	private boolean function acquire(){
		try {
			if ( variables.mutex.tryLock( javacast( "long", 5 ), variables.seconds ) ) {
				return true;
			}
		} catch ( any e ) {
		}
		variables.system.err.println( "errorAlerts throttle lock unavailable; failing open." );
		return false;
	}

	/**
	 * evictExpired
	 *
	 * Deletes expired windows without creating digests.
	 * record() calls this while holding the lock when the registry is full.
	 * Suppressed counts in these windows are lost to keep memory bounded.
	 *
	 * @nowMs The tick count already used by record().
	 */
	private void function evictExpired( required numeric nowMs ){
		for ( var signature in variables.windows.keyArray() ) {
			if ( arguments.nowMs >= variables.windows[ signature ].windowStart + settings.throttle.windowSeconds * 1000 ) {
				variables.windows.delete( signature );
			}
		}
	}

	/**
	 * addSamples
	 *
	 * Adds the snapshot's route and client to the window's distinct-value
	 * sample sets. A value is skipped when blank or already sampled. Once a
	 * set holds settings.digestSampleSize values, new distinct values only set
	 * the overflow flag - the sets sit in a long-lived window entry and must
	 * not grow with traffic. Runs while record() holds the lock.
	 *
	 * @entry    The window entry being updated.
	 * @snapshot The occurrence snapshot from CaptureService.
	 */
	private void function addSamples( required struct entry, required struct snapshot ){
		var capacity = settings.keyExists( "digestSampleSize" ) ? settings.digestSampleSize : 0;
		if ( !capacity ) {
			return;
		}

		for ( var key in [ "route", "client" ] ) {
			if ( !arguments.snapshot.keyExists( key ) || !isSimpleValue( arguments.snapshot[ key ] ) ) {
				continue;
			}
			var value = toString( arguments.snapshot[ key ] ).trim();
			if ( !value.len() || arrayFindNoCase( arguments.entry.samples[ key ], value ) ) {
				continue;
			}
			if ( arguments.entry.samples[ key ].len() >= capacity ) {
				arguments.entry.overflow[ key ] = true;
				continue;
			}
			arguments.entry.samples[ key ].append( value );
		}
	}

	/**
	 * buildSeed
	 *
	 * Returns the expired window fields needed to build a digest.
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
			windowSeconds   : settings.throttle.windowSeconds,
			samples         : arguments.entry.keyExists( "samples" ) ? arguments.entry.samples : { route : [], client : [] },
			overflow        : arguments.entry.keyExists( "overflow" ) ? arguments.entry.overflow : { route : false, client : false }
		};
	}

}
