# AGENTS.md

Guidance for working in this repository. This is a living document and should be updated with critical knowledge that LLMs should be aware of before starting any session.

## What this is

**errorAlerts** is a ColdBox module that watches for exceptions or errors in an applicaiton and emails useful information about the error to the developer.

## Engine support

Lucee 5, 6, Adobe ColdFusion 2023, 2025, BoxLang 1+ (CFML compatible). 

## Common commands

Everything CFML-side runs through [CommandBox](https://commandbox.ortusbooks.com/) (`box`). The embedded
server's webroot is `test-harness/`, and `server.json` aliases the module paths to the repo root, so the
harness loads the module under development without a separate install.

```bash

box run-script start:lucee5           # also: start:lucee6, start:2023, start:2025 (Adobe CF), start:boxlang
box run-script stop:lucee5            # default port 60310
box run-script logs:lucee5

# ALWAYS check before starting a server: the port is shared by every engine.
box server list
```

## Running tests

With a server running, open the TestBox runner:

```
http://127.0.0.1:[port]/tests/runner.cfm                              # full suite
http://127.0.0.1:[port]/tests/runner.cfm?reporter=text                # plain text
http://127.0.0.1:[port]/tests/runner.cfm?bundles=tests.specs.PageTest # one bundle
http://127.0.0.1:[port]/tests/runner.cfm?directory=tests.specs.unit   # one directory
```

CFML specs live in `test-harness/tests/specs/` (`unit/`, `integration/`). Unit specs extend
`tests.resources.BaseUnitSpec` (shared settings and exception fixtures); integration specs extend
`tests.resources.BaseIntegrationSpec` (in-memory mailbox helpers). The integration specs read the
in-memory mailbox, so the harness must be on the `default` mailer before running them - with a
sending mailer active the mailbox stays empty and the specs fail. Request
`/main/mailer?use=default` to switch back without restarting the server; `ERRORALERTS_MAILER` in
`.env` only sets which mailer is active at startup.

The harness registers three mailers: `default` (in memory), `smtp` (a local catcher) and `mailtrap`
(a sandbox inbox you can read on a phone). `mailerDefaults()` in
`test-harness/config/Coldbox.cfc` is the single place their hosts, ports and credentials live, and
both startup and the `/main/mailer` route read it. Do not try to configure a `CFMail` mailer through
its per-mailer `properties`: `CFMailProtocol` never reads them, so connection settings only take
effect as cbmailservices mail defaults. Credentials belong in `.env`, which is gitignored, never in
the committed `.env.example`.

[docs/test-harness.md](docs/test-harness.md) covers the failure scenario catalog on the harness home
page and how to send its alert emails to a local SMTP server so you can read them as real email.

## Code style

- **Method Javadocs:** every method, public and private, carries a javadoc block with `@param` lines.
- **Handler naming:** plural nouns (`Users.cfc`, `Pages.cfc`, `Categories.cfc`).
- **Dependency injection:** prefer `property name="service" inject="Service@cms"` over `getInstance()`.
- **PRC vs RC:** `prc` for internal / server-set data, `rc` for raw user input. Always validate `rc`.
- **Framework reinit:** `?fwreinit=true`.
- Avoid em-dashes in prose unless they genuinely aid clarity.
- Do not run `cfformat` on the repo. 
- This repo uses Git Flow for branching.

## Masking engine invariants

- `defaultSettings()` in `test-harness/tests/resources/BaseUnitSpec.cfc` must mirror the settings
  struct in `ModuleConfig.cfc` key for key. Every unit spec reads that fixture, so adding a setting
  is always a two-file change, in the same commit.
- The masking order is fixed: exact `maskKeys` hash lookup, then `maskKeyPatterns` wildcards only on
  a miss, then long-value truncation. Masking is opt-in - `maskKeys` ships empty - and matching is
  exact by design; substring matching was removed in 2.1.0 because it hid keys like `tokenCount`.
- The sanitizer's walk is budget-bounded: it never collects more content than the output caps
  (`extraInfoMaxLength`, `requestBodyMaxLength`, `rcValueMaxLength`) can display. A cutoff may omit
  content but must never emit a value that skipped the mask check.
- The mask token `*** masked ***` is deliberately not configurable.
- `throttle` and `includeScopes` are the only settings that are structs. ColdBox merges module
  settings one level deep, so a partial override arrives missing its other keys and every unguarded
  `settings.throttle.x` read throws inside `CaptureService`'s catch, which silently sends nothing.
  `ModuleConfig.applyNestedDefaults()` puts the missing keys back at load. Any new struct-valued
  setting must be added to `nestedDefaults()` in the same commit. The harness config sets a
  deliberately partial `includeScopes` so a regression fails the integration specs immediately.
- A request body `isJSON()` accepts is never printed raw. If it cannot be walked - over
  `MAX_PARSE_CHARS`, a parse failure, or a bare scalar - it is reported by size. Anything else has no
  field names to match and prints as sent; that limit is documented in the README rather than hidden.
  `parseJson()` exists as a separate method for the same reason `toJson()` does: engines disagree on
  what `isJSON()` accepts (Adobe rejects a trailing comma Lucee and BoxLang accept), so no literal
  body text reaches the failure paths everywhere. Force those paths through the seam, never with
  malformed text.
- `build()` calls `ensureMaskConfig()` once per alert; everything downstream uses `ensureCompiled()`,
  which only compiles when nothing has been compiled yet. Do not put the fingerprint check back on a
  per-key path - it made a wide `rc` rebuild the fingerprint once per key.
- Objects and queries pass through the walk untouched by design, so keys inside them are never
  mask-checked. Do not "fix" this by calling `getMemento()`: on a Quick or cborm entity that method
  can run database queries through relationships, recurse without a depth cap, and throw, none of
  which is acceptable inside error handling. The `rc` table's `[object com.foo.Bar]` marker is a
  rendering limit for a short-string column, not a different masking policy.
- `stringify()` retries a struct key by key when serializing it as a whole fails, so one value the
  engine refuses cannot discard the entire section. `toJson()` exists as a separate method purely so
  specs can force that failure without depending on an engine-specific unserializable value.
- `test-harness/tests/specs/perf/PayloadBuilderBenchmarkTest.cfc` times alert building against large
  payloads (`?directory=tests.specs.perf`). Run it before and after touching PayloadBuilder's
  sanitize path and compare against the numbers in the relevant commit messages.

## Capture invariants

- `CaptureService.captureException()` is the only public entry point for an unhandled exception.
  The interceptor calls this method for ColdBox requests. An application's `Application.cfc`
  `onError()` calls it directly for pages outside ColdBox. The method must never throw an exception
  back to the caller. A failed alert must not stop the application from showing its error page.
- The unhandled-exception LogEvent message (`Unhandled exception: #message# #detail#`) and the
  `UnhandledException` category help identify matching errors for throttling. Changing either makes
  existing errors count as new groups with new time windows for limiting alerts.
- Call `hasColdBoxContext()` before reading request data through `getRequestService().getContext()`.
  `getContext()` creates a context when none exists. The helper first checks that a context exists,
  then checks for a non-empty `getCurrentEvent()`. Code outside ColdBox can create an empty context
  by calling WireBox, so checking only for a context is not enough. Keep the helper's copies in
  `PayloadBuilder` and `CaptureService` identical. Unit specs replace `PayloadBuilder` with a stub,
  so `CaptureService` needs its own copy.
- Keep the `settings.enabled` check in `capture()`. WireBox can create
  `CaptureService@errorAlerts` even when `ModuleConfig.isActive()` did not register the appender
  and interceptor. Direct calls must still respect the disabled setting. Keep the blank-`to` check
  in `EmailNotifier` too.
- The request key `_errorAlertsCapturing` prevents capture from running again while a capture is
  already in progress. `_errorAlertsReported` tracks errors already reported in the request. Every
  spec in a run shares one runner request. Specs that call `captureException()` must clear both
  keys first. Integration specs use `BaseIntegrationSpec.resetRequestState()` to clear them.
- Adobe puts errors from `Application.cfc` event methods inside an `EventHandlerException`, with
  the original error in `rootCause`. Adobe can also pass an abort to `onError()`. Lucee and BoxLang
  handle aborts elsewhere and use `cause` instead of `rootCause`. Only remove the
  `EventHandlerException` wrapper. A `rootCause` key alone does not mean the error is wrapped;
  ordinary Adobe database and Java exceptions have that key too.
- `captureException()` calls `getModuleService().loadMappings()` before it captures. On Lucee
  and BoxLang, CFML module mappings last one request. These mappings tell CFML where module code
  lives. ColdBox reloads them in `Bootstrap.onRequestStart()`. If `onError()` runs before that
  method, as in the harness's `startFail` scenario, the `cbmailservices` mapping is missing.
  The first attempt to build `Mail@cbmailservices` fails. WireBox then reports "Instance not found"
  for later attempts until the application is reinitialized. Adobe keeps mappings for the whole
  application and does not have this problem. Keep the reload call. If you change it, run the legacy
  scenarios on Lucee or BoxLang, starting with `startFail.cfm`.
- Request data is never trustworthy inside a ColdBox async thread. ColdBox's
  `BaseProxy` copies the request that created a scheduled task or future into its
  executor thread:
  - Adobe: `cgi` is a snapshot of that request.
  - Lucee: the thread gets a dummy page context whose `cgi` says `GET` and `localhost`.
  - BoxLang: the thread's context chain leads back to that request.

  `ThreadClassifier.isAsyncThread()` detects these threads with each engine's own
  mark: Adobe's `FusionContext.isAsyncThread()`, Lucee's dummy page context, and
  BoxLang's `ThreadBoxContext`. If the mark cannot be read, it falls back to the
  JDK executor thread names (`pool-N-thread-M`, `ForkJoinPool...-worker-N`).
  It checks for `cfthread` first, because on Adobe a `cfthread` inherits the async
  flag from its parent. `PayloadBuilder` and `CaptureService.buildSnapshot()` must
  ask it before reading `cgi`, `url`, headers or the ColdBox request context. Every
  engine check is a separate private method, so specs stub them instead of
  starting threads.
- Adobe cannot parse a member call on a parenthesized expression such as
  `( a ? b : c ).left( 200 )`. Adobe reports this as a named-parameter error. Assign the expression's
  result to a variable first, then call the method on that variable.

## Email rendering invariants

`models/EmailRenderer.cfc` builds the whole email as concatenated strings. There are no views.

- The email is a complete HTML document. Its only `<style>` block is `MOBILE_CSS`, which contains a
  single `@media only screen and (max-width:600px)` rule and nothing else. Never put an
  unconditional rule there. Many mail clients strip style blocks, so the desktop layout has to come
  entirely from inline styles. A spec used to assert the email contained no style block at all;
  that assertion was replaced with a narrower one, not dropped, so do not restore it.
- Every element that carries a class must also carry the inline styles that class overrides, and
  the `class` attribute must come immediately before `style`. `EmailRendererTest` checks for the
  literal `class="ea-x" style=`.
- Use only class selectors in `MOBILE_CSS`. An ID selector or a hex color would need `##` escaping
  inside the CFML string, which is easy to get wrong.
- `assemble()` subtracts the measured lengths of `DOC_HEAD` and `DOC_FOOT` from `maxBodyBytes`.
  Growing the document chrome without that subtraction breaks the size cap.
- Adding markup to a per-row helper such as `kvTable()` multiplies across every row. A wide `rc`
  can hold hundreds of rows, so it comes out of the same budget.
- Known limitation, not a regression: on a wide screen one long source line still makes the card
  wider than its 640px maximum. `snippetBlock()` uses `white-space:pre`, and a table cannot shrink
  below the width of its content, so `max-width` cannot clamp it. The media query fixes this on
  small screens only. Changing it would change the desktop layout, so ask before doing so.
- To check a layout change, open `/main/lastMail` on the harness after firing a scenario. It
  renders the newest in-memory email as HTML. Chrome's headless mode pins a 500px minimum window,
  so put the email in a 360px `<iframe>` to test the media query at a real phone width.

## Releasing

This module uses a specific release methodology. See [RELEASE.md](RELEASE.md) for details. Do not bump versions or release unless explicitly asked to do so.
