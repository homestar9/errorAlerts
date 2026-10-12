<cfscript>
/* Application.cfc onRequestStart() throws before this page runs. Adobe wraps
 * that exception in an EventHandlerException on its way to onError(), and the
 * alert must still name Harness.StartFail rather than the wrapper. */
writeOutput( "<p>If you can read this, onRequestStart() did not throw for this page.</p>" );
</cfscript>
