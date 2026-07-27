<cfoutput>
<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>errorAlerts harness</title>
	<style>
		:root { color-scheme: light dark; }
		body {
			font: 15px/1.5 -apple-system, "Segoe UI", system-ui, sans-serif;
			margin: 0; padding: 2rem; max-width: 60rem;
		}
		h1 { margin: 0 0 .25rem; font-size: 1.4rem; }
		h2 { margin: 2rem 0 .5rem; font-size: 1.05rem; border-bottom: 1px solid ##8884; padding-bottom: .3rem; }
		p.lede { margin: 0 0 1.5rem; opacity: .75; }
		table { border-collapse: collapse; width: 100%; }
		td { padding: .35rem .5rem .35rem 0; vertical-align: top; border-bottom: 1px solid ##8882; }
		td.route { white-space: nowrap; width: 15rem; }
		td.note { opacity: .8; font-size: .9rem; }
		a { color: inherit; }
		code, .route a { font-family: ui-monospace, "Cascadia Code", Consolas, monospace; font-size: .88rem; }
		.status { border: 1px solid ##8884; border-radius: 6px; padding: .75rem 1rem; margin-bottom: 1.5rem; }
		.status div { font-family: ui-monospace, Consolas, monospace; font-size: .85rem; }
		.quiet { opacity: .6; }
		button {
			font: inherit; padding: .45rem .9rem; border-radius: 6px;
			border: 1px solid ##8886; background: transparent; color: inherit; cursor: pointer;
		}
		button:disabled { opacity: .5; cursor: default; }
		##log { font-family: ui-monospace, Consolas, monospace; font-size: .8rem; white-space: pre-wrap; margin-top: .75rem; }
	</style>
</head>
<body>
#view()#
</body>
</html>
</cfoutput>
