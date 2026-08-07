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
in-memory mailbox, so unset `ERRORALERTS_MAILER` (remove or edit `.env`) before running them - with
the SMTP mailer active the mailbox stays empty and the specs fail.

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

## Releasing

This module uses a specific release methodology. See [RELEASE.md](RELEASE.md) for details. Do not bump versions or release unless explicitly asked to do so.
