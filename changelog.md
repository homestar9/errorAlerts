# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
