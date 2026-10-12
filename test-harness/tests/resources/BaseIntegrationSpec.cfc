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
	 * resetRequestState
	 *
	 * Clears the request keys that track reported errors and a capture in progress.
	 * All specs in a run share one request. Without this reset, captureException()
	 * could skip a test error because an earlier spec already reported the same error.
	 */
	function resetRequestState(){
		structDelete( request, "_errorAlertsReported" );
		structDelete( request, "_errorAlertsCapturing" );
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
