# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- **Masking is now opt-in: `maskKeys` defaults to an empty array.** The nine
  former default entries (`password`, `passwd`, `token`, `secret`, `apikey`,
  `api_key`, `authorization`, `creditcard`, `cvv`) are gone. An application that
  never set `maskKeys` and relied on those names being hidden must now list its
  own field names; the README's new "Masking and sanitization" section carries a
  starter list to copy. Applications that already set `maskKeys` are unaffected,
  because overriding the setting always replaced the whole list.
- Keys nested inside `rc` values and inside JSON request bodies are now masked.
  Before this, only top-level names were checked, so `rc.payment.cardNumber`
  was serialized into the email in full while a top-level `cardNumber` was
  masked. JSON **array** request bodies, which previously skipped masking
  entirely, are walked too.

### Added

- `maskKeyPatterns` setting: wildcard field-name matching for vendor spellings
  an exact list cannot keep up with, such as `indemnitor1SocialSecurityNumber`.
  `*` matches any run of characters; matching ignores case, covers the whole
  name, and runs only when the exact `maskKeys` lookup misses.
- `longValueMaxLength` setting, default `500`: any string value found while
  walking `extraInfo` or a JSON body keeps this many characters plus a label
  such as `[truncated, 245120 chars total]`. This is the answer to base64 PDFs
  and other blobs landing in payloads. `0` disables the per-value cap.
- `longValueExemptKeys` setting, default `[ "_stacktrace", "stacktrace" ]`:
  values under these keys skip the per-value cap so stack traces keep their
  frames.
- `extraInfoMaxLength` setting, default `2000`: the `extraInfo` output cap,
  previously hardcoded.
- A benchmark suite at `tests/specs/perf` timing alert building against large
  payloads, runnable alone with `?directory=tests.specs.perf`.

### Changed

- The sanitizer was rebuilt around one budget-bounded walk. Masked-key lookup
  is now a hash check, so the length of `maskKeys` no longer affects alert
  cost, and the walk stops collecting once it has enough content to fill the
  email. A 5 MB string in `extraInfo` previously cost a full serialization to
  produce 2,000 characters of email; it now costs a bounded copy. Very wide
  structures stop early and report `[N more keys]` in place of the rest. A
  cutoff can only omit content, never bypass masking.
- Long simple values in the `rc` table now end with the size label instead of a
  bare ellipsis.
- A null `rc` value now renders `[null]`. Before this it threw inside the
  sanitizer and the whole `rc` table silently disappeared from the email.

## [2.4.0] - 2026-08-05

### Security

- `extraInfo` values are now masked with `maskKeys` at any nesting depth, up to
  five levels. Before this, a struct passed as the second argument to
  `logger.error()` was serialized into the email exactly as given, so a key such
  as `password` or `authorization` was printed in full. Applications using
  `coldbox.system.RestHandler` were affected without doing anything: RestHandler
  passes `getHTTPRequestData()` into `extraInfo`, which carries every request
  header, including `Authorization`. The `Cookie` and `Authorization` block in
  the Request section never covered this, because that value arrives through
  `extraInfo` instead of through `includeHeaders`.
- Query parameter values, and an exception's `detail` and `extendedInfo`, are
  still not masked. They carry no field names to match against. This is now
  stated in the README rather than left unsaid.

### Fixed

- Applications whose handlers extend `coldbox.system.RestHandler` no longer
  receive two alert emails for one exception. `RestHandler.onAnyOtherException()`
  logs the exception and then announces `onException` on the next line, so both
  the module's LogBox appender and its interceptor captured the same failure.
  The two copies had different categories and messages, so throttling treated
  them as unrelated errors and sent both. `ignoreCategories` could not filter the
  logged copy, because RestHandler logs under the calling handler's own category,
  which differs for every handler.
- The logged copy is the one dropped. Only the announced copy carries a real
  `tagContext`, so it is the only one that can produce stack frames, an
  application-frame attribution, and a code snippet.
- `RestHandler.onError()` logs the same shape but announces nothing, so its
  alert is kept. Suppressing it would have removed the only report of a
  failure in `preHandler`, `postHandler`, or `aroundHandler`.

### Added

- `suppressDuplicateFrameworkLogs` setting, default `true`. Set it to `false`
  only if you have unregistered the module's `UnhandledExceptionCapture`
  interceptor, since that interceptor reports the copy that is kept.

## [2.3.0] - 2026-08-04

### Changed

- Error signatures now include the first application-owned stack frame, so two
  call sites that fail with the same message throttle separately. Before this,
  every database error hashed the same framework grammar frame and unrelated
  failing queries only differed by message text. Every signature changes once
  on upgrade, which restarts any open throttle window; a burst in progress
  during the deploy may send up to `maxPerWindow` extra emails.
- `relativePaths` now defaults to `true`: paths inside the application root
  render as `/handlers/Main.cfc` instead of the full absolute path. Paths
  outside the root are still shown in full. Set the flag back to `false` for
  absolute paths.

### Added

- The email pins the first stack frame that belongs to the application itself
  (handler, model, view), even when it sits past the `stackFrames` display cap,
  and highlights it in the frame list. Which folders count as application code
  is configurable with `applicationFramePrefixes`.
- A second source snippet, "Application caller", showing the application line
  that asked for the failing work, next to the existing throw-site snippet.
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
- Digest emails list the distinct routes and client IPs seen during the
  throttle window - "3 distinct routes from 1 client IP" identifies a crawler
  at a glance. Capped by the new `digestSampleSize` setting; `0` disables it.
  The client IP row reads the `X-Forwarded-For` header when the request sends
  one, so treat its value as a diagnostic hint rather than proof of origin.

### Internal

These change how the project is built and released. They do not ship in the
published package.

- The release task can publish a version whose tag already exists at HEAD,
  through the new `release:existing-tag` script. This is what a tag-triggered
  CI job needs, since the tag is created before the job runs.
- `release:hotfix` is now also available under the clearer name
  `release:skip-tests`. Both names still work.
- `test:engines` runs every engine even after one fails, then prints a pass or
  fail line for each. It used to stop at the first failure, which hid whether
  the others would have passed.
- The release no longer runs `git checkout -f` before pulling. It uses
  `git pull --ff-only`, so uncommitted work can no longer be discarded by
  starting a release.

## [2.2.0] - 2026-07-28

- Added a project logo

## [2.1.0] - 2026-07-27

### Changed

- **BREAKING:** `maskKeys` now matches field names exactly (ignoring case)
  instead of by substring. A key such as `apiToken`, previously masked by the
  `token` entry, is no longer masked unless listed explicitly. Check the field
  names your forms post and list every variant - `password` no longer covers
  `newPassword`. The change stops unrelated fields such as `tokenCount` from
  disappearing out of diagnostic emails.
- Stack frames whose template is not a file path, such as JDBC driver
  internals, are skipped after the first frame.
- The exception's error code is hidden when it just repeats the database
  block's `sqlState`, which is what Adobe reports for database errors.
- Timestamps now carry a timezone label, since an app that sets
  `this.timezone` reports times in that zone rather than the reader's.
- Throttle-window wording is correct under one minute: a 30-second window now
  reads "30-second" instead of "0 minutes".

### Added

- A source code snippet around the failing line, highlighted, the way
  ColdBox's Whoops page shows it. Controlled by `codeSnippetLines`.
- A Database block for query failures: the failing SQL, datasource, driver
  error codes, and optionally the bound parameter values
  (`includeQueryParams`).
- A "Caused by" list that walks the exception's cause chain, up to five
  levels.
- The exception's error code and `extendedInfo` (where cbValidation puts
  field-level errors).
- A much fuller Request section. Every value the request did not provide shows
  a placeholder (`emptyValueText`) instead of being silently absent. New rows:
  `origin` (the file and line that broke, even for a plain `log.error()` call),
  `user` (via the new `userProvider` closure setting), `routePattern`,
  `routeName`, `routedModule`, `routedNamespace`, `view`, `layout`, `isAjax`,
  `machine`, `context` (web request / scheduled task / background thread),
  `memory` (JVM heap use), `sessionId` (opt-in via `includeScopes.session`),
  `templatePath`, `forwardedFor`, `forwardedProto`, `accept`,
  `acceptLanguage`, `https`, and `serverPort`.
- Request headers in the Request section via the `includeHeaders` allowlist
  (default `Content-Type`). `Cookie` and `Authorization` are never included.
- An optional raw request body section (`includeRequestBody`, off by default)
  for JSON and API endpoints, masked with `maskKeys` and capped at
  `requestBodyMaxLength`.
- The query string is masked with `maskKeys` (`maskQueryString`), closing the
  gap where a secret in a GET URL reached the email unmasked.
- `relativePaths` trims the application root from file paths.
- The digest email names the machine that flushed it.

## [2.0.0] - 2026-07-24

### Removed

- The `environments` setting. Alerts now run in every environment, including
  `development`. To turn them off in one environment, add a function named after that
  environment to `config/modules/errorAlerts.cfc` and set `settings.enabled = false`.
  See "Disable alerts in development" in the README.

## [1.0.0] - 2026-07-24

### Added

- Initial release.
- Email alerts for unhandled exceptions and LogBox errors.
- Per-error throttling with digest summaries.
- Clear HTML emails with request details, stack traces, and secret masking.
- Custom notifier support for non-email alert services.
- Test harness support for Lucee 5, Lucee 6, and Adobe ColdFusion 2025.
