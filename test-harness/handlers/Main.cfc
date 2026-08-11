/**
 * Provides status and manual test actions for the harness.
 */
component {

	/**
	 * index
	 *
	 * Renders the scenario catalog.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function index( event, rc, prc ){
		/* Read the mailer from the service rather than the startup settings, so the
		 * status line stays correct after a runtime switch. */
		var mailService = getInstance( "MailService@cbmailservices" );

		prc.mailer       = mailService.getDefaultProtocol();
		prc.mailDefaults = mailService.getDefaultSettings();
		prc.mailers      = getSetting( "mailerDefaults" ).keyArray().sort( "text" );
		prc.alerts       = getSetting( "moduleSettings" ).errorAlerts;
		prc.database     = getInstance( "DbService" ).describe();
		event.setView( "main/index" );
	}

	/**
	 * mailer
	 *
	 * Switches the active mailer without restarting the server.
	 *
	 * Every mailer is registered at startup, so switching means changing two
	 * things: which mailer is the default, and the connection settings that
	 * newMail() appends onto each message. `.env` still decides which mailer is
	 * active when the server boots.
	 *
	 * @event The current request context.
	 * @rc    The request collection. rc.use names the mailer to switch to.
	 * @prc   The private request collection.
	 */
	function mailer( event, rc, prc ){
		var targets     = getSetting( "mailerDefaults" );
		// rc is user input. An unknown name falls back to the in-memory mailbox.
		var target      = targets.keyExists( rc.use ?: "" ) ? rc.use : "default";
		var mailService = getInstance( "MailService@cbmailservices" );

		/* MailService copies both of these into its own scope at startup, so the
		 * setters are what actually change where mail goes. duplicate() keeps the
		 * harness settings struct out of reach of anything downstream. */
		mailService.setDefaultProtocol( target );
		mailService.setDefaultSettings( duplicate( targets[ target ] ) );

		/* Shorten the throttle window while previewing so a digest arrives about a
		 * minute after a burst instead of ten. ThrottleService reads this setting
		 * on every call, so the new value applies to the next alert. */
		getSetting( "moduleSettings" ).errorAlerts.throttle.windowSeconds = target == "default" ? 600 : 60;

		relocate( "main.index" );
	}

	/**
	 * mailTest
	 *
	 * Sends one plain email through the active mailer and prints the result.
	 *
	 * This is the only way to see a delivery failure. cbmailservices catches send
	 * errors inside the protocol and stores them on the mail object instead of
	 * throwing, so errorAlerts never sees them and nothing reaches the log. A
	 * silent alert is therefore not proof that the mail arrived; this route is.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function mailTest( event, rc, prc ){
		var mailService = getInstance( "MailService@cbmailservices" );
		var alerts      = getSetting( "moduleSettings" ).errorAlerts;
		var mail        = mailService.newMail(
			to      = alerts.to,
			from    = alerts.from.trim().len() ? alerts.from : alerts.to,
			subject = "errorAlerts harness mailer test",
			type    = "html",
			body    = "<p>Sent by /main/mailTest to check the active mailer.</p>"
		);

		mailService.send( mail );

		var results = mail.getResults();
		var out     = [
			"mailer   = #mailService.getDefaultProtocol()#",
			"settings = #mailService.getDefaultSettings().keyList()#",
			"error    = #results.error#",
			"messages = #results.messages.toList( " | " )#"
		];

		event.renderData( type = "text", data = out.toList( chr( 10 ) ) );
	}

	/**
	 * boom
	 *
	 * Throws an exception for a manual alert test.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function boom( event, rc, prc ){
		throw( type = "HarnessBoom", message = "errorAlerts harness test explosion" );
	}

	/**
	 * onException
	 *
	 * Sets the response status for the harness's custom exception handler.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function onException( event, rc, prc ){
		event.setHTTPHeader( statusCode = 500 );
	}

	/**
	 * diag
	 *
	 * Checks module services and sends an error to the in-memory mailbox.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function diag( event, rc, prc ){
		var out = [];
		out.append( "appenderRegistered=" & controller.getLogBox().getAppenderRegistry().keyExists( "errorAlerts" ) );
		try {
			getInstance( "CaptureService@errorAlerts" );
			out.append( "captureService=OK" );
		} catch ( any e ) {
			out.append( "captureService=FAIL #e.message#" );
		}
		try {
			getInstance( "MailService@cbmailservices" );
			out.append( "mailService=OK" );
		} catch ( any e ) {
			out.append( "mailService=FAIL #e.message#" );
		}

		out.append( "mailer=" & getSetting( "moduleSettings" ).cbmailservices.defaultProtocol );
		out.append( "database=" & getInstance( "DbService" ).describe() );

		controller.getLogBox().getLogger( "diagTest" ).error( "diag boom" );

		try {
			var mailbox = getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.getMail();
			out.append( "mailbox=#mailbox.len()#" );
			if ( mailbox.len() ) {
				out.append( "subject=#mailbox[ mailbox.len() ].subject#" );
			}
		} catch ( any e ) {
			out.append( "mailbox=FAIL #e.message#" );
		}

		return out.toList( " | " );
	}

	/**
	 * lastMail
	 *
	 * Renders the HTML body of the newest in-memory email.
	 *
	 * @event The current request context.
	 * @rc    The request collection.
	 * @prc   The private request collection.
	 */
	function lastMail( event, rc, prc ){
		var mailbox = getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.getMail();
		if ( !mailbox.len() ) {
			return "mailbox empty";
		}
		event.renderData( type = "html", data = mailbox[ mailbox.len() ].body );
	}

}
