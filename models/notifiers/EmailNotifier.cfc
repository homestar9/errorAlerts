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
		return this;
	}

	/**
	 * sendNotification
	 *
	 * Builds and delivers one alert or digest email.
	 * Mail failures go to System.err. They cannot break the request or create
	 * another LogBox error.
	 *
	 * Send no email when the to setting is blank. The module does not register
	 * its appender and interceptor in that case, but direct captureException()
	 * calls can still reach this notifier. Print the warning once so repeated
	 * onError() calls do not print the same warning for every error.
	 *
	 * @payload The payload struct from PayloadBuilder.
	 */
	void function sendNotification( required struct payload ){
		try {
			if ( !settings.to.trim().len() ) {
				if ( !variables.keyExists( "warnedBlankTo" ) ) {
					variables.warnedBlankTo = true;
					variables.system.err.println(
						"errorAlerts: setting `to` is blank, so no alert email was sent."
					);
				}
				return;
			}

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
			variables.system.err.println( "errorAlerts email delivery failed: #e.message# #e.detail#" );
		}
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
