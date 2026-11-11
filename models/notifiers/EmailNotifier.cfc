/**
 * EmailNotifier
 *
 * Renders notification payloads and sends them through cbmailservices.
 * Queue mode sends later. Send mode waits for delivery.
 */
component singleton accessors="true" implements="errorAlerts.models.notifiers.INotifier" {

	// The provider loads cbmailservices when the first alert is sent.
	property name="settings"    inject="coldbox:moduleSettings:errorAlerts";
	property name="renderer"    inject="EmailRenderer@errorAlerts";
	property name="mailService" inject="provider:MailService@cbmailservices";

	/**
	 * init
	 *
	 * Stores the Java System object used to write failures to System.err.
	 */
	function init(){
		variables.system = createObject( "java", "java.lang.System" );

		// Cap failure text. cbmailservices puts full stack traces in its result messages.
		variables.MAX_FAILURE_TEXT = 500;

		return this;
	}

	/**
	 * sendNotification
	 *
	 * Builds and delivers one alert or digest email.
	 *
	 * A failure throws errorAlerts.DeliveryFailed. CaptureService catches it,
	 * prints it to System.err, and lets onError() retry the alert. Nothing here
	 * logs through LogBox, so a failure cannot create another alert.
	 *
	 * cbmailservices' send() never throws: it records a failure on the mail
	 * object. Send mode checks that record. Success means the engine accepted
	 * the mail; Adobe and Lucee spool cfmail and deliver it later. Queue mode
	 * only adds the mail to an in-memory queue, so success means queued.
	 *
	 * Send no email when the to setting is blank. The module does not register
	 * its appender and interceptor in that case, but direct captureException()
	 * calls can still reach this notifier. Print the warning once so repeated
	 * onError() calls do not print the same warning for every error.
	 *
	 * @payload The payload struct from PayloadBuilder.
	 */
	void function sendNotification( required struct payload ){
		if ( !settings.to.trim().len() ) {
			if ( !variables.keyExists( "warnedBlankTo" ) ) {
				variables.warnedBlankTo = true;
				variables.system.err.println(
					"errorAlerts: setting `to` is blank, so no alert email was sent."
				);
			}
			return;
		}

		try {
			var mail = mailService.newMail(
				to      = settings.to,
				from    = settings.from.trim().len() ? settings.from : settings.to,
				subject = buildSubject( arguments.payload ),
				type    = "html",
				body    = arguments.payload.type == "digest"
				 ? renderer.renderDigest( arguments.payload )
				 : renderer.renderError( arguments.payload )
			);

			if ( settings.deliveryMode == "send" ) {
				mailService.send( mail );
			} else {
				mailService.queue( mail );
			}
		} catch ( any e ) {
			throwDeliveryFailed( "#e.message# #e.detail#" );
		}

		if ( settings.deliveryMode == "send" && mail.hasErrors() ) {
			throwDeliveryFailed( mail.getResultMessages().toList( " | " ) );
		}
	}

	/**
	 * throwDeliveryFailed
	 *
	 * Throws the exception CaptureService treats as a failed delivery.
	 *
	 * @reason What went wrong, capped before it is thrown.
	 */
	private void function throwDeliveryFailed( required string reason ){
		throw(
			type    = "errorAlerts.DeliveryFailed",
			message = "email delivery failed",
			detail  = arguments.reason.left( variables.MAX_FAILURE_TEXT )
		);
	}

	/**
	 * buildSubject
	 *
	 * Builds an error subject in this form:
	 *   "[prefix] [environment] SEVERITY: first 80 chars of the message"
	 * Digest subjects include the suppressed count. A blank prefix uses the
	 * application name.
	 *
	 * @payload The payload struct being delivered.
	 */
	private string function buildSubject( required struct payload ){
		var parts = [];

		if ( settings.subjectPrefix.trim().len() ) {
			parts.append( settings.subjectPrefix.trim() );
		} else if ( arguments.payload.appName.len() ) {
			parts.append( "[#arguments.payload.appName#]" );
		}

		if ( arguments.payload.environment.len() ) {
			parts.append( "[#arguments.payload.environment#]" );
		}

		if ( arguments.payload.type == "digest" ) {
			parts.append(
				"DIGEST: ""#arguments.payload.message.left( 60 )#"" fired #arguments.payload.suppressedCount# more times"
			);
		} else {
			parts.append( "#arguments.payload.severity#: #arguments.payload.message.left( 80 )#" );
		}

		return parts.toList( " " );
	}

}
