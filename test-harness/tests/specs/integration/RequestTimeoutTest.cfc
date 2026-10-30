/**
 * Tests a real request timeout.
 *
 * - Adobe checks the limit at tags such as cfoutput and throws the timeout again
 *   at every later check, including inside ColdBox's error template.
 * - Lucee stops the request from a controller thread. The stop is an abort, so
 *   it skips ColdBox and reaches Application.cfc's onError(). Lucee then stops
 *   the request again on a later pass while onError() is still reporting.
 * - BoxLang does not enforce the limit, so these specs are skipped there.
 *
 * A timeout cannot run inside the runner request, which sets requestTimeout to
 * 9999 and would be killed. These specs call the harness over HTTP instead. The
 * harness is a separate application with its own in-memory mailbox, so its
 * /main/mailbox route reports what it sent.
 */
component extends="tests.resources.BaseIntegrationSpec" {

	/**
	 * beforeAll
	 *
	 * Renders ColdBox's error template once before the timed specs. The harness
	 * allows only 3 extra seconds after a timeout, and on a freshly started
	 * Adobe server the first Whoops render can spend that compiling the
	 * template, which failed the spec once under memory pressure. beforeEach
	 * clears the alert this sends.
	 */
	function beforeAll(){
		super.beforeAll();
		if ( !server.keyExists( "boxlang" ) ) {
			harnessGet( "/trigger/handlerThrow" );
		}
	}

	/**
	 * run
	 *
	 * Defines the request timeout integration tests.
	 */
	function run(){
		describe(
			title = "A request that runs past its time limit",
			skip  = server.keyExists( "boxlang" ),
			body  = function(){
				beforeEach( function(){
					// Clears the harness throttle windows and mailbox, not the runner's.
					harnessGet( "/trigger/reset" );
				} );

				it( "sends one alert and still renders the error page", function(){
					expectOneTimeoutAlert( "/trigger/requestTimeout" );
				} );

				it( "does the same when one call ran far past the limit plus the extension", function(){
					// Adding the extension to the current limit is not enough here.
					expectOneTimeoutAlert( "/trigger/requestTimeout?overshoot=5" );
				} );
			}
		);
	}

	/**
	 * expectOneTimeoutAlert
	 *
	 * Fires a timeout scenario on the harness and checks the response and the
	 * harness mailbox. Without the extension:
	 * - On Adobe, the error template's cfoutput throws the timeout again, the
	 *   onError() page replaces it, and onError() sends a second alert.
	 * - On Lucee, the second stop lands inside onError(), Lucee shows its own
	 *   error page, and no alert is sent.
	 *
	 * Lucee can still stop the request a second time before onError() reaches
	 * the module, about once in fifteen runs under load. Allow three attempts
	 * there. Without the extension every attempt fails, so a regression still
	 * fails this spec.
	 *
	 * @route The harness route to request.
	 */
	private void function expectOneTimeoutAlert( required string route ){
		var adobe    = !server.keyExists( "lucee" );
		var attempts = adobe ? 1 : 3;
		var result   = {};

		for ( var attempt = 1; attempt <= attempts; attempt++ ) {
			if ( attempt > 1 ) {
				harnessGet( "/trigger/reset" );
			}
			result = fireTimeout( arguments.route, adobe );
			if ( result.passed ) {
				break;
			}
		}

		expect( result.status ).toBe( 500 );
		expect( result.pageRendered ).toBeTrue(
			adobe ? "ColdBox's error template rendered" : "onError() finished its own page"
		);
		expect( result.mailbox.count ).toBe( 1, "exactly one alert: #serializeJSON( result.mailbox.subjects )#" );
		// Subjects keep the first 80 characters, so match each engine's opening words.
		expect( result.mailbox.subjects[ 1 ] ).toInclude(
			adobe ? "exceeded the allowable time limit" : "Unhandled exception: Request ["
		);
	}

	/**
	 * fireTimeout
	 *
	 * Requests one timeout scenario and returns what the response and the
	 * harness mailbox showed, and whether that is the expected result.
	 *
	 * @route The harness route to request.
	 * @adobe Whether the server runs Adobe ColdFusion.
	 */
	private struct function fireTimeout( required string route, required boolean adobe ){
		var response = harnessGet( arguments.route );
		var marker   = arguments.adobe ? "class=""whoops" : "Harness error page";
		var result   = {
			status       : response.status,
			pageRendered : response.body.find( marker ) > 0,
			mailbox      : harnessMailbox()
		};
		result.passed = result.status == 500 && result.pageRendered && result.mailbox.count == 1;
		return result;
	}

	/**
	 * harnessMailbox
	 *
	 * Returns the harness's mailer name, email count and subjects. Fails with a
	 * clear message when the harness is not on the in-memory mailer, because the
	 * count is then always zero.
	 */
	private struct function harnessMailbox(){
		var mailbox = deserializeJSON( harnessGet( "/main/mailbox" ).body );
		if ( mailbox.protocol != "default" ) {
			fail( "The harness uses the '#mailbox.protocol#' mailer. Request /main/mailer?use=default first." );
		}
		return mailbox;
	}

	/**
	 * harnessGet
	 *
	 * Requests a harness route on this server and returns its status and body.
	 * The timeout covers a cold harness start plus the overshoot scenario.
	 *
	 * @route The route, starting with a slash.
	 */
	private struct function harnessGet( required string route ){
		cfhttp(
			url          = "http://#cgi.server_name#:#cgi.server_port##arguments.route#",
			method       = "GET",
			timeout      = 90,
			throwOnError = false,
			result       = "local.response"
		);
		return {
			status : val( local.response.statusCode ),
			body   : toString( local.response.fileContent )
		};
	}

}
