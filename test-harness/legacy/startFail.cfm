<cfscript>
/* Application.cfc onRequestStart() throws before this page runs. Adobe wraps
 * that error in an EventHandlerException before passing it to onError().
 * The alert must show the original error type, Harness.StartFail. */
writeOutput( "<p>If you can read this, onRequestStart() did not throw for this page.</p>" );
</cfscript>
