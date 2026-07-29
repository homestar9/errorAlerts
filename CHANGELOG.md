# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
