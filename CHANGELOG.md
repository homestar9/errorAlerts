# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.7.0] - 2026-10-12

### Added

- `CaptureService.captureException( exception )` reports an exception from code
  that runs outside ColdBox, such as an `Application.cfc` `onError()` method for
  an older folder that shares the ColdBox application. The method checks ignore
  lists, limits repeated alerts, hides values selected by the masking settings,
  and calls the notifier.
  Repeated errors can appear in a digest email for the same time window. The
  method never throws an exception back to the caller. It ignores aborts and
  redirects, reports the original error from Adobe's `EventHandlerException`
  wrapper, and prevents duplicate reports of the same error within a request.
  On Lucee and BoxLang, the method reloads module mappings before reporting an
  error. If `onError()` runs before ColdBox starts handling the request, those
  mappings are missing. Without them, the first mail build fails and later
  alerts fail until the application is reinitialized. See "Pages outside
  ColdBox" in the README for the `onError()` example. The module's interceptor
  now calls this method too.
- The test harness has a "Legacy pages (outside ColdBox)" group of plain `.cfm`
  files under `test-harness/legacy/`. The harness's `Application.cfc` `onError()`
  method reports errors from these files.

### Changed

- Alerts from outside ColdBox, such as legacy pages, scheduled tasks, and
  threads, show one `coldbox` row with "not a ColdBox request" instead of nine
  `N/A` routing rows. For web requests, the request collection (`rc`) combines
  `FORM` and `URL` values and applies `maskKeys`. Building an alert no longer
  creates a ColdBox request context.
- `CaptureService.capture()` checks `enabled` each time it runs. WireBox can
  create the service even when the module did not register its appender and
  interceptor. This check prevents direct calls from sending alerts when the
  module is disabled.
- `EmailNotifier` sends no email when `to` is blank. It prints a console warning
  once.
- Digest emails list the page path for errors from web requests outside ColdBox.

## [2.6.0] - 2026-08-11

### Added

- **The alert email now adjusts to small screens.** On a screen narrower than
  600 pixels each label moves above its value, so long values such as URLs,
  file paths, and `rc` entries use the full width instead of a squeezed column.
  Section padding shrinks from 20 to 12 pixels, and long source lines and stack
  frame paths wrap instead of running off the side. Measured against the test
  harness on a 360 pixel screen, the email went from 1249 pixels wide to 344.
- The email is now a complete HTML document with a viewport meta tag. It used
  to be a bare `<table>` fragment, which left phones to guess the layout width.
- `exceptionFieldMaxLength`, default `2048`, controls how many characters of
  the exception `detail` and `extendedInfo` fields the email shows. Both
  limits were hardcoded at 1024 before. Set `0` to disable the cap;
  `maxBodyBytes` still limits the whole email.

### Changed

- The rendered email carries one `<style>` block holding a single
  `@media only screen and (max-width:600px)` rule, and elements carry `ea-`
  prefixed classes. Every element still carries the inline styles it had
  before, so a mail client that ignores embedded style blocks, such as Outlook
  on Windows, renders the same two-column layout as earlier versions.
- `assemble()` now subtracts the measured length of the document head and
  footer from the `maxBodyBytes` budget instead of assuming a fixed 600
  characters. Without this the larger head could push an email past the cap.

### Known limitation

- On a wide screen a single long line of source code still makes the email card
  wider than its 640 pixel maximum, because the snippet table uses
  `white-space:pre` and a table cannot shrink below its content. This behavior
  is unchanged from earlier versions and only affects wide screens; small
  screens now wrap those lines.

## [2.5.0] - 2026-08-07

### Security

- **Masking is now opt-in.** `maskKeys` defaults to an empty array. The old
  defaults were `password`, `passwd`, `token`, `secret`, `apikey`, `api_key`,
  `authorization`, `creditcard`, and `cvv`. Applications that relied on those
  defaults must now list their own sensitive fields. Applications that already
  set `maskKeys` are not affected. The README provides a starter list.
- Masking now checks nested keys in `rc` values and JSON bodies. Earlier
  versions only checked top-level keys. JSON array bodies are also walked.
- JSON that cannot be walked is reported by size instead of printed raw. This
  includes parse failures, values that are too large to parse, and JSON strings
  or numbers with no field names. Non-JSON bodies are still shown as sent because
  key masking has no field names to check.

### Fixed

- **Partial nested settings no longer stop alerts.** ColdBox replaces nested
  structs instead of merging their keys. A partial `includeScopes` override
  could remove `rc`, `cgi`, and `extraInfo`, which made alert building fail. A
  partial `throttle` override could also disable throttling. Module startup now
  restores missing keys without replacing application values.
- JSON request bodies larger than 2 MB are reported by size. Parsing a larger
  body could use several times the body's size in memory before sanitizing began.
- Query-string masking now refreshes its configuration before reading the first
  field. Tests could previously reuse masking settings from an earlier alert.
- One value rejected by the JSON serializer no longer hides the complete
  section. Structs are retried one key at a time. Readable values stay visible,
  and a failing component or Java object becomes a marker with its type.

### Added

- `maskKeyPatterns` adds wildcard field matching. `*` matches any number of
  characters. Matching ignores case, covers the complete field name, and runs
  only when `maskKeys` has no exact match.
- `longValueMaxLength`, default `500`, limits each string in `extraInfo` or a
  JSON body. Truncated values include their original size. Set it to `0` to
  disable the per-value limit.
- `longValueExemptKeys`, default `[ "_stacktrace", "stacktrace" ]`, keeps
  selected values from using the per-value limit.
- `extraInfoMaxLength`, default `2000`, makes the old hardcoded section limit
  configurable.
- `tests/specs/perf` measures alert building with large payloads. Run it with
  `?directory=tests.specs.perf`.

### Changed

- Sanitizing now uses one shared character budget. Exact field names use a hash
  lookup. Large strings and wide structures stop after enough content has been
  collected. Omitted fields are reported as `[N more keys]`. Every displayed
  value still passes the mask check.
- The masking configuration is compiled once per alert instead of once per `rc`
  key and header.
- Long simple values in the `rc` table now end with the size label instead of a
  bare ellipsis.
- A null `rc` value now renders `[null]` instead of hiding the complete `rc`
  table.

## [2.4.0] - 2026-08-05

### Security

- `maskKeys` now checks `extraInfo` values up to five levels deep. This also
  protects request headers that RestHandler places inside `extraInfo`, including
  `Authorization`. The Request section's header blocklist does not cover this
  separate path.
- Bound query values, exception `detail`, and exception `extendedInfo` remain
  unmasked because they have no field names. The README now states this limit.

### Fixed

- RestHandler exceptions no longer send two alerts. RestHandler logs an action
  error and then announces `onException`. The reports use different categories
  and messages, so throttling could not combine them. Category rules also could
  not match every handler category.
- The logged copy is dropped. Only the `onException` announcement contains the
  tagContext needed for stack frames, application attribution, and source code.
- `RestHandler.onError()` logs without announcing, so its report is kept. This
  covers errors in `preHandler`, `postHandler`, and `aroundHandler`.

### Added

- `suppressDuplicateFrameworkLogs`, default `true`, controls RestHandler
  duplicate removal. Set it to `false` only after unregistering the module's
  `UnhandledExceptionCapture` interceptor.

## [2.3.0] - 2026-08-04

### Changed

- Error signatures now include the first application stack frame. Different
  call sites with the same message use separate throttle windows. This is most
  useful for database errors that share one framework frame. Existing throttle
  windows restart during upgrade and may allow `maxPerWindow` extra emails.
- `relativePaths` now defaults to `true`: paths inside the application root
  render as `/handlers/Main.cfc` instead of the full absolute path. Paths
  outside the root are still shown in full. Set the flag back to `false` for
  absolute paths.

### Added

- The email highlights the first application stack frame, even when it falls
  past the `stackFrames` limit. `applicationFramePrefixes` defines application
  paths.
- An "Application caller" source snippet shows the application line next to the
  throw-site snippet.
- Rows such as "... 5 frames omitted" and "... 3 more frames not shown" mark
  where the stack list is shortened. Previously the list stopped silently at
  ten frames and looked complete.
- Stack frames keep the function name when the engine supplies one.
- A copyable `url` row in the Request section, e.g.
  `GET https://example.com/posts/hello?page=2`, with `maskKeys` applied to the
  query string.
- A Runtime section listing the CFML engine, Java, ColdBox, and errorAlerts
  versions.
- An `elapsed` row showing how long the request had been running when it
  failed, on engines that expose the request start time (Lucee, BoxLang).
- Digest emails list distinct routes and client IP addresses. `digestSampleSize`
  limits both lists, and `0` disables them. A client can control
  `X-Forwarded-For`, so the IP address is a hint rather than proof.

### Internal

These changes only affect project development and release tasks.

- `release:existing-tag` publishes a tag that already points to HEAD. This
  supports CI jobs triggered after a tag is created.
- `release:hotfix` is now also available under the clearer name
  `release:skip-tests`. Both names still work.
- `test:engines` runs and reports every engine even after one fails.
- Releases use `git pull --ff-only` instead of `git checkout -f`. Starting a
  release can no longer discard uncommitted work.

## [2.2.0] - 2026-07-28

- Added a project logo

## [2.1.0] - 2026-07-27

### Changed

- **BREAKING:** `maskKeys` now matches complete field names and ignores case.
  It no longer uses substring matching. For example, `token` does not match
  `apiToken` or `tokenCount`. List every sensitive field name explicitly.
- Stack frames whose template is not a file path, such as JDBC driver
  internals, are skipped after the first frame.
- The exception's error code is hidden when it just repeats the database
  block's `sqlState`, which is what Adobe reports for database errors.
- Timestamps now include a timezone label. An application may use a different
  timezone from the person reading the email.
- Throttle-window wording is correct under one minute: a 30-second window now
  reads "30-second" instead of "0 minutes".

### Added

- A highlighted source snippet around the failing line. `codeSnippetLines`
  controls its size.
- A Database block for query failures: the failing SQL, datasource, driver
  error codes, and optionally the bound parameter values
  (`includeQueryParams`).
- A "Caused by" list with up to five exception cause levels.
- The exception's error code and `extendedInfo` (where cbValidation puts
  field-level errors).
- A larger Request section. Missing request values show `emptyValueText`. New rows:
  `origin` (the file and line that broke, even for a plain `log.error()` call),
  `user` (via the new `userProvider` closure setting), `routePattern`,
  `routeName`, `routedModule`, `routedNamespace`, `view`, `layout`, `isAjax`,
  `machine`, `context` (web request / scheduled task / background thread),
  `memory` (JVM heap use), `sessionId` (opt-in via `includeScopes.session`),
  `templatePath`, `forwardedFor`, `forwardedProto`, `accept`,
  `acceptLanguage`, `https`, and `serverPort`.
- Request headers selected by `includeHeaders`, which defaults to `Content-Type`.
  `Cookie` and `Authorization` are always blocked.
- An optional raw request body section (`includeRequestBody`, off by default)
  for JSON and API endpoints, masked with `maskKeys` and capped at
  `requestBodyMaxLength`.
- `maskQueryString` applies `maskKeys` to GET query strings.
- `relativePaths` trims the application root from file paths.
- The digest email names the machine that flushed it.

## [2.0.0] - 2026-07-24

### Removed

- The `environments` setting. Alerts now run in every environment. To disable
  one environment, add a matching function to `config/modules/errorAlerts.cfc`
  and set `settings.enabled = false`. The README contains an example.

## [1.0.0] - 2026-07-24

### Added

- Initial release.
- Email alerts for unhandled exceptions and LogBox errors.
- Per-error throttling with digest summaries.
- Clear HTML emails with request details, stack traces, and secret masking.
- Custom notifier support for non-email alert services.
- Test harness support for Lucee 5, Lucee 6, and Adobe ColdFusion 2025.
