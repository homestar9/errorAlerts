<cfscript>
/* Redirect, then stop the request, as an older login check might do.
 * This page must send no email on any engine. Adobe can pass the abort to
 * onError() as coldfusion.runtime.AbortException, which the module ignores.
 * Lucee and BoxLang handle aborts without calling onError(). */
location( url = "/", addToken = false );
abort;
</cfscript>
