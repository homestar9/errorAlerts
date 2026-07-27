<cfoutput>
	<!--- The view has already rendered into the body by the time this runs. --->
	<h2>Site header</h2>

	<!--- prc.navigation was never set, so the layout throws after the view worked. --->
	<cfloop array="#prc.navigation#" index="link">
		<a href="#link.href#">#link.label#</a>
	</cfloop>

	#view()#
</cfoutput>
