/**
 * INotifier
 *
 * Defines notification delivery. CaptureService passes an "error" or "digest"
 * payload from PayloadBuilder to sendNotification().
 *
 * Implementations must handle their own failures and must not log them at
 * ERROR because that can call ErrorAlertAppender again. CaptureService catches
 * thrown failures as a final safeguard.
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
