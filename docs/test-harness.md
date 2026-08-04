# Test harness

The harness is a small ColdBox application under `test-harness/` that loads the
module straight from the working tree. It exists so alert emails can be produced
on demand and read as real email, not just asserted on in a test.

Start a server and open <http://127.0.0.1:60310/>. The home page lists every
failure scenario as a link, shows which mailer is active, and has a button that
fires them all in sequence.

## Sending real email

By default the harness keeps sent mail in memory, because the TestBox specs read
that mailbox. To send to a local SMTP server instead:

```bash
cp .env.example .env      # already gitignored
box run-script start:2023
```

`.env` sets `ERRORALERTS_MAILER=smtp`, which does three things in
`test-harness/config/Coldbox.cfc`:

- switches cbmailservices to its `CFMail` mailer, which sends through the
  `cfmail` tag to `ERRORALERTS_SMTP_SERVER:ERRORALERTS_SMTP_PORT`
- turns mail spooling off, so a delivery failure shows up straight away instead
  of being queued
- shortens the throttle window to 60 seconds and the digest flush to 20, so a
  digest email arrives about a minute after a burst instead of ten

Leave `ERRORALERTS_MAILER` unset and everything goes back to the in-memory
mailbox. `/main/lastMail` renders the newest in-memory email in the browser.

## The scenario catalog

`test-harness/handlers/Trigger.cfc` has one action per scenario, grouped by which
part of the module handles it.

**Unhandled exceptions** reach the module through
`interceptors/UnhandledExceptionCapture.cfc`. The harness sets
`exceptionHandler : "main.onException"`, and ColdBox does not log the exception
when an application does that, so the appender never sees it. These scenarios
cover a bare `throw()`, failures several components deep, engine-native errors
(undefined variable, type mismatch, divide by zero, missing method, bad array
index, null reference), failures while rendering a view or a layout, a failure
inside an interceptor, a WireBox constructor failure, a high-level error that
wraps a low-level one, file and HTTP failures, and requests for events that do
not exist.

One engine difference worth knowing: Lucee's `throw()` takes a `cause` argument
and Adobe's does not. Adobe rejects it while compiling, even on a branch that
would never run on Adobe, so `models/PaymentGateway.cfc` carries the original
error in `extendedInfo` instead.

**Database failures** need an in-memory database. `Application.cfc` declares two
datasources because no engine ships both drivers — Adobe gets Derby from
`cfpm install derby` and Lucee 6 bundles HSQLDB. `models/DbService.cfc` tries
each once, keeps whichever connects, and creates a small `orders` table. The
home page says which one is in use. If neither driver is present, the two
portable scenarios (`dbNoDatasource`, `dbDeadHost`) still produce real database
exceptions on any engine.

**Manual LogBox messages** reach the module through
`models/ErrorAlertAppender.cfc` on the root logger. These cover an error with no
exception attached, a caught exception passed as `extraInfo`, a plain data struct
as `extraInfo`, a FATAL, and a log call from a background thread where there is
no request context. Three of them deliberately produce nothing: `logWarn` and
`logInfo` are below `levelMin`, and `logIgnoredCategory` uses a category that
starts with `cbmailservices`, which is in `ignoreCategories`. An email from any
of those three is a bug.

**Throttling and digests** fire the same error repeatedly so the first-N and
digest behavior can be watched. `/trigger/flushDigest` sends any pending digest
immediately rather than waiting for the scheduler. `/trigger/reset` clears every
throttle window.

**Email content checks** exist to be read rather than counted — masking of
sensitive `rc` keys, awkward value types in `rc`, markup that must not render as
markup, non-ASCII text, an oversized message, and a POST so the Request section
shows something other than GET.

## What a run on Adobe 2023 showed

Findings from firing the whole catalog, worth knowing before you read your own
run:

- **Query-string values are masked since 2.1.0.** An earlier run on this catalog
  found `/trigger/maskedRc` masking secrets in the Request collection section
  while the Request section above it printed `cgi.query_string` verbatim. The
  `maskQueryString` setting (on by default) now applies `maskKeys` to the query
  string row. Note that matching is exact since 2.1.0: `creditCardNumber` is
  only masked if the app lists it - the default entry `creditcard` no longer
  covers it by substring.
- **A REST handler failure alerts twice.** `/api/boom` produces two emails: one
  from `RestHandler.onError()`, which logs at ERROR under the `handlers.Api`
  category and so reaches the appender, and one from the module's `onException`
  interceptor. A plain handler produces one.
- **`maxBodyBytes` is rarely what clips an email.** `/trigger/hugeMessage` throws
  a 250KB message with a 250KB detail and the email arrives at about 12KB,
  because `EmailRenderer` caps the message section at 2048 characters first.
  `maxBodyBytes` only matters when many medium-sized sections add up.
- Escaping, the `stackFrames` limit and signature normalization all behaved:
  markup arrived as literal text, and `/trigger/burstVariants` collapsed 10
  messages that differed only by numbers and UUIDs into a single throttle window.
- **The stack list can hold one more frame than `stackFrames` allows.**
  `/trigger/deepStack` shows 11 frames out of 25: the ten the `stackFrames` cap
  permits, plus the first application-owned frame pinned on the end so the email
  always names the line of your own code that triggered the error. Rows reading
  `... N frames omitted` and `... N more frames not shown` mark where the list was
  shortened, so it never looks complete when it is not.

## Adding a scenario

Two edits:

1. Add the action to `test-harness/handlers/Trigger.cfc`. Actions that should
   alert do not catch anything. Actions that should not alert return a line
   saying why.
2. Add a row to the `groups` array at the top of
   `test-harness/views/main/index.cfm`. Set `alerts : false` when no email is
   expected, `skipAll : true` to leave it out of the sweep, and `method : "POST"`
   to render it as a form button instead of a link.

## Running the specs

```bash
box run-script start:2023
```

then <http://127.0.0.1:60310/tests/runner.cfm>. Unset `ERRORALERTS_MAILER`
first — the integration specs read the in-memory mailbox, and with the SMTP
mailer active it stays empty.
