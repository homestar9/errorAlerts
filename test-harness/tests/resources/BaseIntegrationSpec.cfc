/**
 * Runs integration specs against the loaded module and in-memory mailer.
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	// Load ColdBox once and share it across test bundles.
	this.loadColdBox   = true;
	this.unloadColdBox = false;

	/**
	 * beforeAll
	 *
	 * Connects this spec to WireBox before its tests run.
	 */
	function beforeAll(){
		super.beforeAll();
		application.wirebox.autowire( this );
	}

	/**
	 * getMailbox
	 *
	 * Returns the emails stored by the in-memory mailer.
	 */
	array function getMailbox(){
		return getInstance( "MailService@cbmailservices" )
			.getMailer( "default" )
			.transit
			.getMail();
	}

	/**
	 * clearMailbox
	 *
	 * Removes every email from the in-memory mailbox.
	 */
	function clearMailbox(){
		getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.reset();
	}

	/**
	 * resetThrottle
	 *
	 * Clears all throttle windows before another test runs.
	 */
	function resetThrottle(){
		getInstance( "ThrottleService@errorAlerts" ).reset();
	}

	/**
	 * newExceptionInfo
	 *
	 * Builds exception data for the unhandled-exception tests.
	 *
	 * @message The exception message, varied per spec to control signatures.
	 */
	struct function newExceptionInfo( string message = "Integration explosion" ){
		return {
			type       : "HarnessBoom",
			message    : arguments.message,
			detail     : "Deliberate integration test exception",
			stacktrace : "java.lang.Exception: #arguments.message#",
			tagContext : [ { template : "/test-harness/handlers/Main.cfc", line : 21 } ]
		};
	}

}
