/**
 * INotifier
 *
 * Defines notification delivery. CaptureService passes an error or digest
 * payload from PayloadBuilder to sendNotification().
 *
 * Implementations must handle their own failures. They must not log failures at
 * ERROR because that can call ErrorAlertAppender again. CaptureService catches
 * any failure that still escapes.
 */
interface {

	/**
	 * sendNotification
	 *
	 * Delivers one notification payload.
	 *
	 * @payload The payload struct from PayloadBuilder ("error" or "digest").
	 */
	void function sendNotification( required struct payload );

}
