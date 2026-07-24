/**
 * Base for integration specs: drives the REAL loaded module (appender,
 * interceptor, throttle, notifier, InMemory mailer) inside the virtual app.
 */
component extends="coldbox.system.testing.BaseTestCase" appMapping="/root" {

	// Load on first test, keep alive between bundles.
	this.loadColdBox   = true;
	this.unloadColdBox = false;

	/**
	 * Wires the spec itself so getInstance() and injections work.
	 */
	function beforeAll(){
		super.beforeAll();
		application.wirebox.autowire( this );
	}

	/**
	 * The InMemory protocol's sent-mail array. Each entry is the struct from
	 * Mail.getConfig(): to / from / subject / body / type and friends.
	 */
	array function getMailbox(){
		return getInstance( "MailService@cbmailservices" )
			.getMailer( "default" )
			.transit
			.getMail();
	}

	/**
	 * Empties the InMemory mailbox.
	 */
	function clearMailbox(){
		getInstance( "MailService@cbmailservices" ).getMailer( "default" ).transit.reset();
	}

	/**
	 * Clears all throttle windows so each spec starts from a clean slate.
	 */
	function resetThrottle(){
		getInstance( "ThrottleService@errorAlerts" ).reset();
	}

	/**
	 * A cfcatch-shaped struct for driving the unhandled-exception path.
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
