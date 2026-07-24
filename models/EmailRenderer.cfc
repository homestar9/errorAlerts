/**
 * EmailRenderer
 *
 * Renders payload structs as table-based HTML with inline styles.
 * PayloadBuilder sanitizes request data before it reaches this component.
 * Sections are added in priority order until the character budget is used.
 */
component singleton accessors="true" {

	// WireBox injects the module settings.
	property name="settings" inject="coldbox:moduleSettings:errorAlerts";

	// Reuse these inline styles. CFML renders ## as one # in color values.
	variables.FONT       = "font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;";
	variables.MONO       = "font-family:Consolas,Menlo,'Courier New',monospace;";
	variables.LABEL_CELL = "padding:4px 10px 4px 0;vertical-align:top;white-space:nowrap;color:##71717a;font-size:12px;#variables.FONT#";
	variables.VALUE_CELL = "padding:4px 0;vertical-align:top;word-break:break-word;color:##18181b;font-size:12px;#variables.MONO#";
	variables.TITLE      = "margin:0 0 6px 0;color:##3f3f46;font-size:13px;font-weight:bold;#variables.FONT#";

	/**
	 * renderError
	 *
	 * Renders one error alert email.
	 *
	 * @payload The error payload from PayloadBuilder.build().
	 */
	string function renderError( required struct payload ){
		var middle = [ messageSection( arguments.payload ) ];

		if ( !arguments.payload.exception.isEmpty() ) {
			middle.append( exceptionSection( arguments.payload.exception ) );
		}
		if ( !arguments.payload.request.isEmpty() ) {
			middle.append( kvSection( "Request", arguments.payload.request ) );
		}
		if ( !arguments.payload.rc.isEmpty() ) {
			middle.append( kvSection( "Request collection (rc)", arguments.payload.rc ) );
		}
		if ( isSimpleValue( arguments.payload.extraInfo ) && arguments.payload.extraInfo.len() ) {
			middle.append( section( "Extra info", preBlock( arguments.payload.extraInfo ) ) );
		}

		return assemble(
			errorHeader( arguments.payload ),
			middle,
			footer( arguments.payload )
		);
	}

	/**
	 * renderDigest
	 *
	 * Renders a digest for suppressed occurrences.
	 *
	 * @payload The digest payload from PayloadBuilder.buildDigest().
	 */
	string function renderDigest( required struct payload ){
		var counts                    = structNew( "ordered" );
		counts[ "Total occurrences" ] = arguments.payload.totalCount;
		counts[ "Sent immediately" ]  = arguments.payload.sentCount;
		counts[ "Suppressed" ]        = arguments.payload.suppressedCount;
		counts[ "Window" ]            = "#int( arguments.payload.windowSeconds / 60 )# minutes";
		counts[ "First seen" ]        = stamp( arguments.payload.firstSeen );
		counts[ "Last seen" ]         = stamp( arguments.payload.lastSeen );
		counts[ "Category" ]          = arguments.payload.category;

		var middle = [
			messageSection( arguments.payload ),
			kvSection( "Burst summary", counts )
		];

		return assemble(
			digestHeader( arguments.payload ),
			middle,
			footer( arguments.payload )
		);
	}

	/**
	 * assemble
	 *
	 * Adds sections in order until the configured character budget is reached.
	 * Stops at the first section that does not fit and adds a notice.
	 *
	 * @head    The header row html.
	 * @middle  The array of middle section rows, in priority order.
	 * @foot    The footer row html.
	 */
	private string function assemble( required string head, required array middle, required string foot ){
		// Reserve 600 characters for the wrapper and truncation notice.
		var budget    = settings.maxBodyBytes - arguments.head.len() - arguments.foot.len() - 600;
		var kept      = [];
		var truncated = false;

		for ( var block in arguments.middle ) {
			if ( block.len() > budget ) {
				truncated = true;
				break;
			}
			kept.append( block );
			budget -= block.len();
		}

		if ( truncated ) {
			kept.append(
				"<tr><td style=""padding:10px 20px;color:##71717a;font-size:12px;#variables.FONT#"">" &
				"Email truncated at #int( settings.maxBodyBytes / 1024 )# KB. See the server logs for full detail." &
				"</td></tr>"
			);
		}

		return wrapDocument( arguments.head & kept.toList( "" ) & arguments.foot );
	}

	/**
	 * wrapDocument
	 *
	 * Wraps the rows in the outer email tables.
	 *
	 * @inner The concatenated <tr> rows of the card.
	 */
	private string function wrapDocument( required string inner ){
		return "<table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" style=""background:##f4f4f5;padding:16px 0;#variables.FONT#"">" &
		"<tr><td align=""center"" style=""padding:8px;"">" &
		"<table role=""presentation"" width=""640"" cellpadding=""0"" cellspacing=""0"" style=""max-width:640px;width:100%;background:##ffffff;border:1px solid ##e4e4e7;"">" &
		arguments.inner &
		"</table></td></tr></table>";
	}

	/**
	 * errorHeader
	 *
	 * Renders the error heading and occurrence details.
	 *
	 * @payload The error payload.
	 */
	private string function errorHeader( required struct payload ){
		var meta = [];
		if ( arguments.payload.appName.len() ) {
			meta.append( esc( arguments.payload.appName ) );
		}
		if ( arguments.payload.environment.len() ) {
			meta.append( esc( arguments.payload.environment ) );
		}
		meta.append( stamp( arguments.payload.timestamp ) );
		meta.append( "occurrence #arguments.payload.occurrence# of #arguments.payload.maxPerWindow# sent per #int( arguments.payload.windowSeconds / 60 )#-minute window" );

		return "<tr><td style=""background:##b91c1c;color:##ffffff;padding:14px 20px;"">" &
		"<div style=""font-size:16px;font-weight:bold;#variables.FONT#"">#esc( arguments.payload.severity )# &middot; #esc( arguments.payload.category )#</div>" &
		"<div style=""font-size:12px;margin-top:4px;color:##fecaca;#variables.FONT#"">#meta.toList( " &middot; " )#</div>" &
		"</td></tr>";
	}

	/**
	 * digestHeader
	 *
	 * Renders the digest heading and suppressed count.
	 *
	 * @payload The digest payload.
	 */
	private string function digestHeader( required struct payload ){
		var meta = [];
		if ( arguments.payload.appName.len() ) {
			meta.append( esc( arguments.payload.appName ) );
		}
		if ( arguments.payload.environment.len() ) {
			meta.append( esc( arguments.payload.environment ) );
		}
		meta.append( "#arguments.payload.suppressedCount# suppressed occurrences" );

		return "<tr><td style=""background:##fef3c7;color:##92400e;padding:14px 20px;"">" &
		"<div style=""font-size:16px;font-weight:bold;#variables.FONT#"">DIGEST &middot; #esc( arguments.payload.severity )#</div>" &
		"<div style=""font-size:12px;margin-top:4px;#variables.FONT#"">#meta.toList( " &middot; " )#</div>" &
		"</td></tr>";
	}

	/**
	 * messageSection
	 *
	 * Renders the first 2,048 characters of the message.
	 *
	 * @payload The payload carrying `message`.
	 */
	private string function messageSection( required struct payload ){
		return section( "Message", preBlock( arguments.payload.message.left( 2048 ) ) );
	}

	/**
	 * exceptionSection
	 *
	 * Renders the exception type, detail, and stack frames.
	 *
	 * @exception The payload.exception struct.
	 */
	private string function exceptionSection( required struct exception ){
		var body = "";

		if ( arguments.exception.type.len() ) {
			body &= "<div style=""margin:0 0 4px 0;font-size:12px;#variables.MONO#color:##18181b;""><strong>#esc( arguments.exception.type )#</strong></div>";
		}
		if ( arguments.exception.detail.len() ) {
			body &= preBlock( arguments.exception.detail.left( 1024 ) );
		}

		if ( arguments.exception.tagContext.len() ) {
			var frames = [];
			for ( var i = 1; i <= arguments.exception.tagContext.len(); i++ ) {
				var frame = arguments.exception.tagContext[ i ];
				var bg    = i % 2 == 0 ? "##f4f4f5" : "##ffffff";
				frames.append(
					"<tr><td style=""padding:3px 8px;font-size:11px;#variables.MONO#color:##3f3f46;background:#bg#;"">" &
					"#i#. #esc( frame.template )#:#esc( frame.line )#" &
					"</td></tr>"
				);
			}
			body &= "<table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" style=""margin-top:6px;border:1px solid ##e4e4e7;"">#frames.toList( "" )#</table>";
		}

		return section( "Exception", body );
	}

	/**
	 * kvSection
	 *
	 * Renders a flat struct as a label and value table.
	 *
	 * @title The section title.
	 * @data  The flat struct to render.
	 */
	private string function kvSection( required string title, required struct data ){
		var rows = [];
		for ( var key in arguments.data ) {
			rows.append(
				"<tr><td style=""#variables.LABEL_CELL#"">#esc( key )#</td>" &
				"<td style=""#variables.VALUE_CELL#"">#esc( arguments.data[ key ] )#</td></tr>"
			);
		}
		return section(
			arguments.title,
			"<table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"">#rows.toList( "" )#</table>"
		);
	}

	/**
	 * section
	 *
	 * Wraps a title and body in a standard email row.
	 *
	 * @title The section title.
	 * @body  The section content html.
	 */
	private string function section( required string title, required string body ){
		return "<tr><td style=""padding:14px 20px;border-top:1px solid ##f4f4f5;"">" &
		"<div style=""#variables.TITLE#"">#esc( arguments.title )#</div>" &
		arguments.body &
		"</td></tr>";
	}

	/**
	 * preBlock
	 *
	 * Escapes text and renders it in a pre-wrapped block.
	 *
	 * @text The raw text to display.
	 */
	private string function preBlock( required string text ){
		return "<div style=""white-space:pre-wrap;word-break:break-word;font-size:12px;line-height:1.5;#variables.MONO#color:##18181b;"">#esc( arguments.text )#</div>";
	}

	/**
	 * footer
	 *
	 * Renders the throttle note, signature, and module version.
	 *
	 * @payload The payload carrying signature/moduleVersion.
	 */
	private string function footer( required struct payload ){
		var note = arguments.payload.type == "digest"
		 ? "This digest summarizes occurrences suppressed after the first #settings.throttle.maxPerWindow# alerts of a window."
		 : "After #settings.throttle.maxPerWindow# alerts, further occurrences of this error are suppressed for #int( settings.throttle.windowSeconds / 60 )# minutes and summarized in a digest.";

		return "<tr><td style=""padding:12px 20px;border-top:1px solid ##e4e4e7;background:##fafafa;color:##a1a1aa;font-size:11px;#variables.FONT#"">" &
		"#note#<br/>" &
		"signature #esc( arguments.payload.keyExists( "signature" ) ? arguments.payload.signature : "" )# &middot; errorAlerts #esc( arguments.payload.moduleVersion )#" &
		"</td></tr>";
	}

	/**
	 * esc
	 *
	 * Converts a value to HTML-safe text.
	 * Returns a placeholder when conversion fails.
	 *
	 * @value The value to encode.
	 */
	private string function esc( required any value ){
		try {
			return encodeForHtml( isSimpleValue( arguments.value ) ? toString( arguments.value ) : serializeJSON( arguments.value ) );
		} catch ( any e ) {
			return "[unrenderable]";
		}
	}

	/**
	 * stamp
	 *
	 * Formats a timestamp for display.
	 *
	 * @value The date/time to format.
	 */
	private string function stamp( required any value ){
		try {
			return dateTimeFormat( arguments.value, "yyyy-mm-dd HH:nn:ss" );
		} catch ( any e ) {
			return toString( arguments.value );
		}
	}

}
