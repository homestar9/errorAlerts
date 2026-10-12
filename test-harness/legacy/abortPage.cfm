<cfscript>
/* location() followed by abort, the pattern a legacy login check uses. No
 * email must arrive on any engine. Adobe can hand the abort to onError() as
 * coldfusion.runtime.AbortException, which the module ignores. Lucee and
 * BoxLang route aborts away from onError() on their own. */
location( url = "/", addToken = false );
abort;
</cfscript>
