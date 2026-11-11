/**
 * INotifier
 *
 * Defines notification delivery. CaptureService passes an error or digest
 * payload from PayloadBuilder to sendNotification().
 *
 * Report a failed delivery by throwing. CaptureService catches the exception,
 * prints it to System.err, and treats the alert as not sent, so an
 * Application.cfc onError() retry of the same exception can send it again.
 * Each attempt counts toward throttle.maxPerWindow. Implementations must not
 * log failures at ERROR because that can call ErrorAlertAppender again.
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
