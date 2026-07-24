/**
 * INotifier
 *
 * The delivery contract. CaptureService resolves `settings.notifier` (any
 * WireBox ID) and calls sendNotification() with payload structs from
 * PayloadBuilder -- `payload.type` is "error" or "digest". Implementations MUST
 * swallow their own failures: a notifier may never throw into the failing
 * request, and may never log at ERROR through LogBox (that would feed the very
 * appender that triggered it).
 */
interface {

	/**
	 * Delivers one notification payload.
	 *
	 * @payload The payload struct from PayloadBuilder ("error" or "digest").
	 */
	void function sendNotification( required struct payload );

}
