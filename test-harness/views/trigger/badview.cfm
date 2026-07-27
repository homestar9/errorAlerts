<cfoutput>
	<!--- Some output happens first so the response is half written when it fails. --->
	<h1>Invoice #prc.invoiceNumber#</h1>
	<p>Rendering line items...</p>

	<!--- prc.lineItems was never set, so this throws part-way through the view. --->
	<cfloop array="#prc.lineItems#" index="item">
		<p>#item.description#</p>
	</cfloop>

	<p>This line never renders.</p>
</cfoutput>
