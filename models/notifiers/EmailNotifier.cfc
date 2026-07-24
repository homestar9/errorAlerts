/**
 * EmailNotifier
 *
 * The shipped INotifier: renders the payload with EmailRenderer and delivers it
 * through cbmailservices. With deliveryMode "queue" (the default) the SMTP
 * round-trip happens on the cbmailservices queue task, off the failing request;
 * "send" delivers synchronously.
 */
component singleton accessors="true" implements="errorAlerts.models.notifiers.INotifier" {

	// Injected properties. The provider keeps load order flexible: cbmailservices
	// is only resolved the first time an alert actually sends.
	property name="settings"    inject="coldbox:moduleSettings:errorAlerts";
	property name="renderer"    inject="EmailRenderer@errorAlerts";
	property name="mailService" inject="provider:MailService@cbmailservices";

	/**
	 * Constructor. Grabs the System handle used for stderr failure notes.
	 */
	function init(){
		variables.system = createObject( "java", "java.lang.System" );
		return this;
	}

	/**
	 * Builds and delivers one alert or digest email. The whole body is wrapped
	 * in try/catch: mail failures go to System.err only, never into the request
	 * and never through LogBox (see INotifier).
	 *
	 * @payload The payload struct from PayloadBuilder.
	 */
	void function sendNotification( required struct payload ){
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
			variables.system.err.println( "errorAlerts email delivery failed: #e.message# #e.detail#" );
		}
	}

	/**
	 * Builds the subject line:
	 *   "[prefix] [environment] SEVERITY: first 80 chars of the message"
	 * Digests use "DIGEST:" plus the suppressed count. The prefix falls back to
	 * "[appName]" when settings.subjectPrefix is blank.
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
