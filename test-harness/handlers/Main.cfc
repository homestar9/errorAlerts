/**
 * Harness main handler: a home action, a manual smoke-test action that throws,
 * and the custom exception handler the harness config points at.
 */
component {

	/**
	 * Confirms the harness is up.
	 */
	function index( event, rc, prc ){
		return "errorAlerts harness up";
	}

	/**
	 * Throws on purpose so a human (or a browser-driven test) can watch the
	 * whole pipeline fire: hit /main/boom five times fast and expect three
	 * alert emails plus one digest after the window closes.
	 */
	function boom( event, rc, prc ){
		throw( type = "HarnessBoom", message = "errorAlerts harness test explosion" );
	}

	/**
	 * The custom exceptionHandler. Deliberately does nothing beyond the status
	 * code -- proving the module needs no host cooperation to capture the error.
	 */
	function onException( event, rc, prc ){
		event.setHTTPHeader( statusCode = 500 );
	}

	/**
	 * Reports whether the module's pieces resolved and whether a logged error
	 * lands in the InMemory mailbox. For manual smoke testing only.
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
	 * Returns the raw HTML body of the newest InMemory mail, so a human can
	 * eyeball the rendered email. For manual smoke testing only.
	 */
	function lastMail( event, rc, prc ){
		var mailbox = getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.getMail();
		if ( !mailbox.len() ) {
			return "mailbox empty";
		}
		event.renderData( type = "html", data = mailbox[ mailbox.len() ].body );
	}

}
