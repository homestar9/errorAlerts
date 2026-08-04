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
		// Engine, Java, ColdBox, and errorAlerts versions. Guarded by keyExists
		// so a payload from an older module version still renders.
		if ( arguments.payload.keyExists( "runtime" ) && !arguments.payload.runtime.isEmpty() ) {
			middle.append( kvSection( "Runtime", arguments.payload.runtime ) );
		}
		if ( !arguments.payload.rc.isEmpty() ) {
			middle.append( kvSection( "Request collection (rc)", arguments.payload.rc ) );
		}
		if (
			arguments.payload.keyExists( "requestBody" )
			&& isSimpleValue( arguments.payload.requestBody )
			&& arguments.payload.requestBody.len()
		) {
			middle.append( section( "Request body", preBlock( arguments.payload.requestBody ) ) );
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
		counts[ "Window" ]            = windowLabel( arguments.payload.windowSeconds );
		counts[ "First seen" ]        = stamp( arguments.payload.firstSeen );
		counts[ "Last seen" ]         = stamp( arguments.payload.lastSeen );
		counts[ "Category" ]          = arguments.payload.category;
		// Which server flushed this digest. Throttle counts are per JVM, so
		// behind a load balancer each machine reports its own burst.
		if ( arguments.payload.keyExists( "machine" ) && toString( arguments.payload.machine ).len() ) {
			counts[ "Machine" ] = arguments.payload.machine;
		}
		// Distinct routes and client addresses seen during the window. "3 routes
		// from 1 client IP" reads as a crawler; "1 route from 40 IPs" does not.
		var sampleRow = sampleSummary( arguments.payload, "route" );
		if ( sampleRow.len() ) {
			counts[ "Routes" ] = sampleRow;
		}
		sampleRow = sampleSummary( arguments.payload, "client" );
		if ( sampleRow.len() ) {
			counts[ "Client IPs" ] = sampleRow;
		}

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
	 * sampleSummary
	 *
	 * Formats one digest sample set as "3 distinct: a, b, c", or
	 * "at least 5 distinct: a, b, c, d, e" when the cap was hit and more
	 * values were seen. Plain words rather than "5+" because encodeForHtml()
	 * turns "+" into an entity, which garbles text assertions and screen
	 * readers. Returns an empty string when the payload has no samples for
	 * the key, so older digest payloads render without the row.
	 *
	 * @payload The digest payload.
	 * @key     "route" or "client".
	 */
	private string function sampleSummary( required struct payload, required string key ){
		if (
			!arguments.payload.keyExists( "samples" )
			|| !arguments.payload.samples.keyExists( arguments.key )
			|| !arguments.payload.samples[ arguments.key ].len()
		) {
			return "";
		}

		var values   = arguments.payload.samples[ arguments.key ];
		var overflow = arguments.payload.keyExists( "overflow" )
		 && arguments.payload.overflow.keyExists( arguments.key )
		 && arguments.payload.overflow[ arguments.key ];
		var prefix = overflow ? "at least " : "";

		return "#prefix##values.len()# distinct: #values.toList( ", " )#";
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
		meta.append( "occurrence #arguments.payload.occurrence# of #arguments.payload.maxPerWindow# sent per #windowText( arguments.payload.windowSeconds )# window" );

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

		// Read through locals so an older payload without these keys still renders.
		var errorCode    = arguments.exception.keyExists( "errorCode" ) ? arguments.exception.errorCode : "";
		var extendedInfo = arguments.exception.keyExists( "extendedInfo" ) ? arguments.exception.extendedInfo : "";
		var db           = arguments.exception.keyExists( "database" ) ? arguments.exception.database : {};
		var causes       = arguments.exception.keyExists( "causes" ) ? arguments.exception.causes : [];
		var snippet      = arguments.exception.keyExists( "snippet" ) ? arguments.exception.snippet : { lines : [] };
		var callerSnippet = arguments.exception.keyExists( "callerSnippet" ) ? arguments.exception.callerSnippet : { lines : [] };

		if ( arguments.exception.type.len() ) {
			// Adobe puts the SQLSTATE in errorCode for a database error, so the
			// code would just repeat the sqlState row below. Show it only when
			// it says something the Database block does not.
			var showCode = errorCode.len()
			 && !( db.keyExists( "sqlState" ) && errorCode == db.sqlState );
			var code = showCode
			 ? " <span style=""color:##71717a;"">(code #esc( errorCode )#)</span>"
			 : "";
			body &= "<div style=""margin:0 0 4px 0;font-size:12px;#variables.MONO#color:##18181b;""><strong>#esc( arguments.exception.type )#</strong>#code#</div>";
		}
		if ( arguments.exception.detail.len() ) {
			body &= preBlock( arguments.exception.detail.left( 1024 ) );
		}

		// The failing code itself. First because it is usually the whole answer.
		// With two snippets, "Throw site" and "Application caller" tell the
		// reader which is which; alone, the familiar "Source" label stays.
		if ( snippet.lines.len() ) {
			var snippetLabel = callerSnippet.lines.len() ? "Throw site" : "Source";
			body &= subTitle( "#snippetLabel# - #snippet.template#:#snippet.line#" );
			body &= snippetBlock( snippet.lines );
		}

		// The application's own line that asked for the failing work.
		if ( callerSnippet.lines.len() ) {
			body &= subTitle( "Application caller - #callerSnippet.template#:#callerSnippet.line#" );
			body &= snippetBlock( callerSnippet.lines );
		}

		// The failing SQL and the driver's own codes. Shown before the stack
		// frames because on a query failure this is what identifies the problem.
		if ( db.count() ) {
			body &= subTitle( "Database" );
			if ( db.keyExists( "sql" ) ) {
				body &= preBlock( db.sql );
			}
			var codes = structNew( "ordered" );
			for ( var key in db ) {
				if ( key != "sql" ) {
					codes[ key ] = db[ key ];
				}
			}
			if ( codes.count() ) {
				body &= kvTable( codes );
			}
		}

		if ( extendedInfo.len() ) {
			body &= subTitle( "Extended info" );
			body &= preBlock( extendedInfo.left( 1024 ) );
		}

		// A framework often catches a low-level error and throws its own, which
		// leaves the real reason here rather than in the message above.
		if ( causes.len() ) {
			body &= subTitle( "Caused by" );
			for ( var cause in causes ) {
				body &= "<div style=""margin:0 0 4px 0;font-size:12px;#variables.MONO#color:##18181b;"">" &
				"<strong>#esc( cause.type )#</strong> #esc( cause.message )#" &
				( cause.detail.len() ? "<br/><span style=""color:##71717a;"">#esc( cause.detail )#</span>" : "" ) &
				"</div>";
			}
		}

		if ( arguments.exception.tagContext.len() ) {
			var totalFrames = arguments.exception.keyExists( "totalFrames" ) ? arguments.exception.totalFrames : 0;
			var frames      = [];
			var lastIndex   = 0;

			for ( var i = 1; i <= arguments.exception.tagContext.len(); i++ ) {
				var frame = arguments.exception.tagContext[ i ];
				// Older payloads have no index/application/fn keys; numbering
				// then falls back to the row position, exactly as before.
				var index = frame.keyExists( "index" ) ? frame.index : i;
				var isApp = frame.keyExists( "application" ) && frame.application;
				var fn    = frame.keyExists( "fn" ) ? frame.fn : "";

				// A jump in the raw position means frames were skipped, either
				// driver noise or the gap before a pinned application frame.
				if ( lastIndex && index > lastIndex + 1 ) {
					var gap = index - lastIndex - 1;
					frames.append( omittedRow( "... #gap# #gap == 1 ? "frame" : "frames"# omitted" ) );
				}

				// Application frames get a blue tint and bold text so the
				// reader's eye lands on their own code first.
				var bg     = isApp ? "##dbeafe" : ( i % 2 == 0 ? "##f4f4f5" : "##ffffff" );
				var color  = isApp ? "##1e40af" : "##3f3f46";
				var weight = isApp ? "bold" : "normal";
				var fnNote = fn.len() ? " <span style=""color:##a1a1aa;font-weight:normal;"">&middot; #esc( fn )#</span>" : "";

				frames.append(
					"<tr><td style=""padding:3px 8px;font-size:11px;#variables.MONO#color:#color#;font-weight:#weight#;background:#bg#;"">" &
					"#index#. #esc( frame.template )#:#esc( frame.line )##fnNote#" &
					"</td></tr>"
				);
				lastIndex = index;
			}

			// Say when the list stops short. Without this row a ten-frame email
			// looks like the whole stack, which misleads during diagnosis.
			if ( totalFrames > lastIndex ) {
				var tail = totalFrames - lastIndex;
				frames.append( omittedRow( "... #tail# more #tail == 1 ? "frame" : "frames"# not shown" ) );
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
		return section( arguments.title, kvTable( arguments.data ) );
	}

	/**
	 * kvTable
	 *
	 * Renders a flat struct as a label and value table, without a section wrapper,
	 * so it can also sit inside another section.
	 *
	 * @data The flat struct to render.
	 */
	private string function kvTable( required struct data ){
		var rows = [];
		for ( var key in arguments.data ) {
			rows.append(
				"<tr><td style=""#variables.LABEL_CELL#"">#esc( key )#</td>" &
				"<td style=""#variables.VALUE_CELL#"">#esc( arguments.data[ key ] )#</td></tr>"
			);
		}
		return "<table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"">#rows.toList( "" )#</table>";
	}

	/**
	 * snippetBlock
	 *
	 * Renders numbered source lines with the failing one highlighted in red.
	 * A table rather than a <pre> block, because Outlook collapses leading
	 * whitespace in a pre and the indentation is half the point.
	 *
	 * @lines Array of { number, text, isError } from PayloadBuilder.
	 */
	private string function snippetBlock( required array lines ){
		var rows = [];

		for ( var item in arguments.lines ) {
			var bg     = item.isError ? "##fee2e2" : "##ffffff";
			var color  = item.isError ? "##b91c1c" : "##3f3f46";
			var weight = item.isError ? "bold" : "normal";

			rows.append(
				"<tr>" &
				"<td style=""padding:2px 8px;width:1%;text-align:right;background:#bg#;color:##a1a1aa;font-size:11px;#variables.MONO#"">#esc( item.number )#</td>" &
				"<td style=""padding:2px 8px;background:#bg#;color:#color#;font-weight:#weight#;font-size:11px;white-space:pre;#variables.MONO#"">#esc( item.text )#</td>" &
				"</tr>"
			);
		}

		return "<table role=""presentation"" width=""100%"" cellpadding=""0"" cellspacing=""0"" style=""margin-top:4px;border:1px solid ##e4e4e7;"">#rows.toList( "" )#</table>";
	}

	/**
	 * omittedRow
	 *
	 * A gray italic row for the stack frame table marking frames that are not
	 * shown, so the list never looks complete when it is not.
	 *
	 * @text The already-plain text to show. Escaped here.
	 */
	private string function omittedRow( required string text ){
		return "<tr><td style=""padding:3px 8px;font-size:11px;#variables.MONO#color:##a1a1aa;font-style:italic;background:##fafafa;"">#esc( arguments.text )#</td></tr>";
	}

	/**
	 * subTitle
	 *
	 * A small heading for a block nested inside a section.
	 *
	 * @text The heading text.
	 */
	private string function subTitle( required string text ){
		return "<div style=""margin:10px 0 4px 0;color:##71717a;font-size:11px;font-weight:bold;text-transform:uppercase;#variables.FONT#"">#esc( arguments.text )#</div>";
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
		 : "After #settings.throttle.maxPerWindow# alerts, further occurrences of this error are suppressed for #windowLabel( settings.throttle.windowSeconds )# and summarized in a digest.";

		return "<tr><td style=""padding:12px 20px;border-top:1px solid ##e4e4e7;background:##fafafa;color:##a1a1aa;font-size:11px;#variables.FONT#"">" &
		"#note#<br/>" &
		"signature #esc( arguments.payload.keyExists( "signature" ) ? arguments.payload.signature : "" )# &middot; errorAlerts #esc( arguments.payload.moduleVersion )#" &
		"</td></tr>";
	}

	/**
	 * windowText
	 *
	 * Describes a throttle window in whole minutes, or in seconds when it is
	 * under a minute. Dividing by 60 alone printed "0 minutes" for a short
	 * window, which is what a test or a fast-cycling window looks like.
	 *
	 * @seconds The window length in seconds.
	 */
	private string function windowText( required numeric seconds ){
		if ( arguments.seconds < 60 ) {
			return "#int( arguments.seconds )#-second";
		}

		var minutes = int( arguments.seconds / 60 );
		return "#minutes#-minute";
	}

	/**
	 * windowLabel
	 *
	 * The same window length worded as a noun, for sentences and table values
	 * where "10-minute" on its own would not read correctly.
	 *
	 * @seconds The window length in seconds.
	 */
	private string function windowLabel( required numeric seconds ){
		if ( arguments.seconds < 60 ) {
			var secs = int( arguments.seconds );
			return "#secs# second#secs == 1 ? "" : "s"#";
		}

		var minutes = int( arguments.seconds / 60 );
		return "#minutes# minute#minutes == 1 ? "" : "s"#";
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
			var zone = zoneLabel();
			return dateTimeFormat( arguments.value, "yyyy-mm-dd HH:nn:ss" ) & ( zone.len() ? " #zone#" : "" );
		} catch ( any e ) {
			return toString( arguments.value );
		}
	}

	/**
	 * zoneLabel
	 *
	 * Names the timezone the timestamps are written in. An application that sets
	 * `this.timezone` reports times in that zone rather than the reader's, so a
	 * bare "16:54:07" is ambiguous. Prefers the application's own setting and
	 * falls back to the JVM default. Cached, since neither value changes.
	 */
	private string function zoneLabel(){
		if ( variables.keyExists( "cachedZone" ) ) {
			return variables.cachedZone;
		}

		var zone = "";

		try {
			var meta = getApplicationMetadata();
			if ( meta.keyExists( "timezone" ) && isSimpleValue( meta.timezone ) && meta.timezone.len() ) {
				zone = meta.timezone;
			}
		} catch ( any e ) {
		}

		if ( !zone.len() ) {
			try {
				zone = createObject( "java", "java.util.TimeZone" ).getDefault().getID();
			} catch ( any e ) {
			}
		}

		// Cache only a real label, so one failed lookup is retried next time.
		if ( zone.len() ) {
			variables.cachedZone = zone;
		}

		return zone;
	}

}
