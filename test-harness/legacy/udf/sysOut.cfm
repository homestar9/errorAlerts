<cfscript>
/**
 * sysOut
 *
 * Writes a value to the console. Application.cfc includes this file, so the
 * function becomes one of its methods, as in applications that keep UDFs in
 * shared include files. functionInUrl.cfm copies it into url.
 *
 * @value The value to write.
 */
function sysOut( value ){
	writeDump( var = arguments.value, output = "console" );
}
</cfscript>
