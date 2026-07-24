# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - Unreleased

### Added

- First release.
- `ErrorAlertAppender`: a LogBox appender that self-registers on the root logger at module load. No host logBox config changes needed.
- `UnhandledExceptionCapture` interceptor: captures unhandled exceptions in hosts that define their own `exceptionHandler` (ColdBox never logs those through LogBox).
- First-N + digest throttling per error signature, with digit/UUID normalization so messages that differ only by ids throttle together.
- Gmail-safe HTML alert emails: inline styles only, no `writeDump()`, hard size cap, secret-key masking.
- Swappable notifier seam (`settings.notifier`) for future non-email delivery (e.g. Sentry).
- Scheduled task that flushes pending digests every 60 seconds so quiet sites still get them.
