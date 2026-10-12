<cfscript>
/* Reads a variable that was never set, so the engine's own undefined-variable
 * error reaches Application.cfc onError() from a page outside ColdBox. */
writeOutput( neverDefinedLegacyVariable );
</cfscript>
