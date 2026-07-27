/**
 * Provides status and manual test actions for the harness.
 */
component {

	/**
	 * index
	 *
	 * Renders the scenario catalog.
	 */
	function index( event, rc, prc ){
		prc.mailer       = getSetting( "moduleSettings" ).cbmailservices.defaultProtocol;
		prc.mailDefaults = getSetting( "moduleSettings" ).cbmailservices.defaults;
		prc.alerts       = getSetting( "moduleSettings" ).errorAlerts;
		prc.database     = getInstance( "DbService" ).describe();
		event.setView( "main/index" );
	}

	/**
	 * boom
	 *
	 * Throws an exception for a manual alert test.
	 */
	function boom( event, rc, prc ){
		throw( type = "HarnessBoom", message = "errorAlerts harness test explosion" );
	}

	/**
	 * onException
	 *
	 * Sets the response status for the harness's custom exception handler.
	 */
	function onException( event, rc, prc ){
		event.setHTTPHeader( statusCode = 500 );
	}

	/**
	 * diag
	 *
	 * Checks module services and sends an error to the in-memory mailbox.
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
	 */
	function lastMail( event, rc, prc ){
		var mailbox = getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.getMail();
		if ( !mailbox.len() ) {
			return "mailbox empty";
		}
		event.renderData( type = "html", data = mailbox[ mailbox.len() ].body );
	}

}
