<cfsetting showdebugoutput="false" >
<!--- Keep test links in this window when cpu is true. --->
<cfparam name="url.cpu" default="false">
<!--- Set the directory displayed by the test browser. --->
<cfset rootMapping 	= "/tests/specs">
<cfif directoryExists( rootMapping )>
	<cfset rootPath = rootMapping>
<cfelse>
	<cfset rootPath = expandPath( rootMapping )>
</cfif>

<!--- Read the requested directory. --->
<cfparam name="url.path" default="/">

<!--- Use the root when no directory was requested. --->
<cfif !len( url.path )>
	<cfset url.path = "/">
</cfif>
<!--- Remove parent-directory segments so browsing stays under the test root. --->
<cfset url.path = replaceNoCase( url.path, '../', '', 'all' )>
<cfset url.path = replaceNoCase( url.path, '..\', '', 'all' )>

<!--- Create the TestBox runner. --->
<cfset testbox = new testbox.system.TestBox()>

<!--- Run all tests under the requested directory. --->
<cfif structKeyExists( url, "action")>
	<cfif directoryExists( expandPath( rootMapping & url.path ) )>
		<cfoutput>#testbox.init( directory=rootMapping & url.path ).run()#</cfoutput>
	<cfelse>
		<cfoutput><h2>Invalid incoming directory: #rootMapping & url.path#</h2></cfoutput>
	</cfif>
	<cfabort>

</cfif>

<!--- List the requested directory. --->
<cfdirectory action="list" directory="#rootPath & url.path#" name="qResults" sort="directory asc, name asc">
<!--- Build the path used to run a selected test. --->
<cfset executePath = rootMapping & ( url.path eq "/" ? "/" : url.path & "/" )>
<!--- Build the link to the parent directory. --->
<cfif url.path neq "/">
	<cfset backPath = replacenocase( url.path, listLast( url.path, "/" ), "" )>
	<cfset backPath = reReplace( backpath, "/$", "" )>
</cfif>

<cfset ASSETS_DIR = expandPath( "/testbox/system/reports/assets" )>
<!--- Render the test browser. --->
<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<meta name="generator" content="TestBox v#testbox.getVersion()#">
	<title>TestBox Browser</title>
	<cfoutput>
		<style>#fileRead( '#ASSETS_DIR#/css/main.css' )#</style>
		<script>#fileRead( '#ASSETS_DIR#/js/jquery-3.3.1.min.js' )#</script>
		<script>#fileRead( '#ASSETS_DIR#/js/popper.min.js' )#</script>
		<script>#fileRead( '#ASSETS_DIR#/js/bootstrap.min.js' )#</script>
		<script>#fileRead( '#ASSETS_DIR#/js/stupidtable.min.js' )#</script>
		<script>#fileRead( '#ASSETS_DIR#/js/fontawesome.js' )#</script>
	</cfoutput>

</head>
<cfoutput>
<body>

<!--- Render the browser heading and test list. --->
<div id="tb-runner" class="container">
	<div class="row">
		<div class="col-md-4 text-center mx-auto">
			<img class="mt-3" src="https://www.ortussolutions.com/__media/testbox-185.png" alt="TestBox" id="tb-logo"/>
			<br>
			v#testbox.getVersion()#
			<br>
			<a href="index.cfm?action=runTestBox&path=#URLEncodedFormat( url.path )#" target="_blank"><button class="btn btn-primary btn-sm my-1" type="button">Run All</button></a>
		</div>
	</div>
	<div class="row">
		<div class="col-md-12">
			<form name="runnerForm" id="runnerForm">
				<input type="hidden" name="opt_run" id="opt_run" value="true">
				<h2>TestBox Test Browser: </h2>
				<p>
					Below is a listing of the files and folders starting from your root <code>#rootPath#</code>.  You can click on individual tests in order to execute them
					or click on the <strong>Run All</strong> button on your left and it will execute a directory runner from the visible folder.
				</p>

				<fieldset>
					<legend>Contents: #executePath#</legend>
					<cfif url.path neq "/">
						<a href="index.cfm?path=#URLEncodedFormat( backPath )#"><button type="button" class="btn btn-secondary btn-sm my-1"><i class="fas fa-angle-double-left"></i> Back</button></a><br><hr>
					</cfif>
					<cfloop query="qResults">
						<cfif refind( "^\.", qResults.name )>
							<cfcontinue>
						</cfif>

						<cfset dirPath = URLEncodedFormat( ( url.path neq '/' ? '#url.path#/' : '/' ) & qResults.name )>
						<cfif qResults.type eq "Dir">
							<a class="btn btn-secondary btn-sm my-1" href="index.cfm?path=#dirPath#"><i class="fas fa-plus"></i> #qResults.name#</a><br/>
						<cfelseif listLast( qresults.name, ".") eq "cfm">
							<a class="btn btn-primary btn-sm my-1" href="#executePath & qResults.name#" <cfif !url.cpu>target="_blank"</cfif>>#qResults.name#</a><br/>
						<cfelseif listLast( qresults.name, ".") eq "cfc" and qresults.name neq "Application.cfc">
							<a class="btn btn-primary btn-sm my-1" href="#executePath & qResults.name#?method=runRemote" <cfif !url.cpu>target="_blank"</cfif>>#qResults.name#</a><br/>
						<cfelse>
							#qResults.name#<br/>
						</cfif>

					</cfloop>
				</fieldset>
			</form>
		</div>
	</div>
</div>

</body>
</html>
</cfoutput>
