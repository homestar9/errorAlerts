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

## Writing style for Code Comments and Responses

Use clear, literal, plain English. **Optimize for immediate understanding, not cleverness or brevity.**

Follow these rules:

- Write for an 8th grade reading level.
- Lead with the direct answer or conclusion.
- Explain the reasoning in a logical order.
- Use one main idea per sentence.
- Use technical terminology when it is the clearest term, but explain unfamiliar or project-specific terms.
- Use concrete descriptions instead of metaphors, idioms, or conversational shorthand.
- Do not assume that shorter writing is clearer writing.
- Do not use the following phrases:
  - "dead input,"
  - "survives,"
  - "the machinery,"
  - "wires up,"
  - "drives,"
  - "gates,"
  - "surfaces"
  - "holding pen"
  - "graduate"
  - "remounts"
- Favor literal language that explains behavior more clearly.
 
Before sending an explanation, reread it and ask:

1. Would a developer unfamiliar with this codebase understand every sentence on the first reading?
2. Does every pronoun have an obvious referent?
3. Did I skip any reasoning needed to connect the evidence to the conclusion?
4. Did I use a clever phrase where a literal explanation would be clearer?

If any answer is no, rewrite the response before sending it.

## Use the Right Subagent For the Job

When delegating work to sub-agents, use the least expensive model that can complete each task reliably. Use lightweight models for mechanical work such as locating files, reading straightforward code, gathering facts, or running simple checks. Use robust reasoning models for architecture, complex debugging, security review, open-ended exploration, creative work, or tasks requiring judgment. When complexity or risk is uncertain, favor the stronger model, and escalate if a lightweight agent encounters ambiguity.

If something the user says is unclear, ask the user questions until you have a solid understanding.

## Releasing

This module uses a specific release methodology. See [RELEASE.md](RELEASE.md) for details. Do not bump versions or release unless explicitly asked to do so.
