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

box run-script start:lucee5           # also: start:lucee6, start:2023 (Adobe CF), start:boxlang
box run-script stop:lucee5            # default port 60301
box run-script logs:lucee5e

# ALWAYS check before starting a server: the port is shared.
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

CFML specs live in `test-harness/tests/specs/` (`unit/`, `integration/`). Vitest specs sit beside the JS
they test. Playwright specs are at the repo root in `tests/e2e/`.

[docs/testing.md](docs/testing.md) covers how to write a spec and the helpers you must use
(`stubRequestHeaders()`, `primeCurrentUser()`, `deleteRoute()`). Reaching for the obvious alternative
fails in non-obvious ways, so read it before writing your first integration spec.

## Code style

- **Method Javadocs:** every method, public and private, carries a javadoc block with `@param` lines.
- **Handler naming:** plural nouns (`Users.cfc`, `Pages.cfc`, `Categories.cfc`).
- **Dependency injection:** prefer `property name="service" inject="Service@cms"` over `getInstance()`.
- **PRC vs RC:** `prc` for internal / server-set data, `rc` for raw user input. Always validate `rc`.
- **Framework reinit:** `?fwreinit=true`.
- Avoid em-dashes in prose unless they genuinely aid clarity.
- Do not run `cfformat` on the repo. 

## Communication style

Write comments, plans, and explanations for a beginner developer. Prefer clear, plain language over dense jargon. Briefly explain non-obvious framework behavior, conventions, or architectural decisions. Keep explanations practical, concise, and easy to scan. Challenge me if you think I am going down the wrong path, introducing unnecessary complexity, or making a decision that will make future maintenance harder. Let me know if I am introducing code-smells, and suggest a better approach. If something I say is unclear, ask me questions until you have a solid understanding.