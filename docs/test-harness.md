# Test harness

The harness is a small ColdBox application under `test-harness/` that loads the
module straight from the working tree. It exists so alert emails can be produced
on demand and read as real email, not just asserted on in a test.

Start a server and open <http://127.0.0.1:60310/>. The home page lists every
failure scenario as a link, shows which mailer is active, and has a button that
fires them all in sequence.

## Sending real email

By default the harness keeps sent mail in memory, because the TestBox specs read
that mailbox. To send real email instead, use the mailer links in the status
block on the home page, or request the route directly:

```text
/main/mailer?use=smtp        # a local mail catcher, such as DevNull SMTP
/main/mailer?use=mailtrap    # a Mailtrap sandbox inbox
/main/mailer?use=default     # back to the in-memory mailbox
```

No restart is needed. Every mailer is registered when the server starts, so the
route only changes which one is the default and which connection settings go out
with each message. It also shortens the throttle window to 60 seconds while a
sending mailer is active, so a digest arrives about a minute after a burst
instead of ten. The switch lasts until the server restarts.

**Reading alerts on a phone.** Use the `mailtrap` mailer. A local catcher writes
`.eml` files to your own disk, which is awkward to open on a phone, while a
Mailtrap inbox is a web app you can log into from the phone itself. Note that
Mailtrap renders each email inside its own preview pane, so the small-screen
media query responds to that pane rather than to the phone's screen width; use
Mailtrap's mobile-preview toggle and its HTML check for an honest reading of the
responsive layout.

### Where the connection settings live

`mailerDefaults()` in `test-harness/config/Coldbox.cfc` holds the host, port and
credentials for every mailer, and both startup and `/main/mailer` read it, so
each value is written once. Adding a mailer means adding an entry there plus a
`{ class : "CFMail" }` line in the `mailers` struct. No handler or view change is
needed: the route validates `rc.use` against the registered names and the home
page renders one link per mailer.

Per-mailer `properties` do **not** work for a `CFMail` mailer.
`CFMailProtocol.mailIt()` only reads the mail payload's own config and never
looks at the protocol's properties, so connection settings have to travel as mail
defaults, which `newMail()` appends onto every message. `Mail.configure()`
accepts `server`, `port`, `username`, `password` and `useTLS` as real arguments,
so each one reaches the `cfmail` tag.

The specs read the in-memory mailbox, so switch back to `default` before running
them. An empty mailbox and a wall of failing integration specs usually means the
harness was left on a sending mailer.

### Setting the startup mailer

`ERRORALERTS_MAILER` in `.env` decides which mailer is active when the server
boots, and `.env` is also where the Mailtrap credentials go:

```bash
cp .env.example .env      # already gitignored
box run-script start:2023
```

Copy the username and password from your Mailtrap inbox's SMTP settings into
`ERRORALERTS_MAILTRAP_USERNAME` and `ERRORALERTS_MAILTRAP_PASSWORD`. Keep real
credentials out of `.env.example`, which is committed.

Setting `ERRORALERTS_MAILER` to anything but `default` does three things in
`test-harness/config/Coldbox.cfc`:

- switches cbmailservices to its `CFMail` mailer, which sends through the
  `cfmail` tag to that mailer's entry in `mailerDefaults()`
- turns mail spooling off, so a delivery failure shows up straight away instead
  of being queued
- shortens the throttle window to 60 seconds and the digest flush to 20, so a
  digest email arrives about a minute after a burst instead of ten

An unrecognized name falls back to the in-memory mailbox rather than failing to
start. Leave `ERRORALERTS_MAILER` unset and the server starts in memory anyway.

CommandBox reads `.env` only at startup, so changing it needs a full server
restart. That is why the `/main/mailer` route exists. The one thing the route
cannot change is `digestFlushSeconds`, because a scheduled task reads it when the
module loads; use `/trigger/flushDigest` to send a digest on demand instead.

`/main/lastMail` renders the newest in-memory email in the browser.

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

`/trigger/taskFailure` arms the harness's ColdBox scheduled task
(`test-harness/config/Scheduler.cfc`, `harnessFailingTask`), which then fails on
its next run, about a second later. The task's `onFailure()` handler logs the
failure through the `harness.tasks` logger, so one email arrives. ColdBox's own
two `ERROR` lines for the failure go only to the console, because the harness
LogBox config sends `coldbox.system` to the console appender only. ColdBox's app
template has the same config. ColdBox copies the request that started the
application into the task's thread. The email must say
`scheduled task (pool-N-thread-M)` and show no URL, event, `rc`, or other row
from that copied request. `ScheduledTaskTest` checks the same thing on every
engine.

**Throttling and digests** fire the same error repeatedly so the first-N and
digest behavior can be watched. `/trigger/flushDigest` sends any pending digest
immediately rather than waiting for the scheduler. `/trigger/reset` clears every
throttle window.

**Email content checks** exist to be read rather than counted — masking of
sensitive `rc` keys, secrets nested inside containers next to a ~400 KB base64
blob (`/trigger/nestedSecrets`, which must also build its alert without a
noticeable pause), awkward value types in `rc`, markup that must not render as
markup, non-ASCII text, an oversized message, and a POST so the Request section
shows something other than GET. The module ships with an empty `maskKeys` —
masking is opt-in — so the harness opts in through its own `moduleSettings` in
[config/Coldbox.cfc](../test-harness/config/Coldbox.cfc); that list is what the
masking routes and the TestBox specs rely on.

**Legacy pages (outside ColdBox)** are plain `.cfm` files under
`test-harness/legacy/`. They test errors from older pages that run without
ColdBox. The harness's `Bootstrap.onRequestStart()` runs ColdBox only for
`index.cfm`. Errors from the legacy pages reach `Application.cfc`'s `onError()`
method, which calls `CaptureService.captureException()`. The
[pages outside ColdBox example](reference.md#pages-outside-coldbox) shows how to
use the same setup for a folder that shares the ColdBox application.

The harness adds `/legacy/` to `applicationFramePrefixes` so stack frames from
these files count as application code. `startFail.cfm` makes `onRequestStart()`
throw an error. Adobe passes that error to `onError()` inside an
`EventHandlerException`. The alert must show the original `Harness.StartFail`
error. `abortPage.cfm` calls `location()` and then `abort`. This page must send
no email on any engine.

An alert for a legacy page shows a `coldbox` row with "not a ColdBox request"
instead of routing rows. Its request collection (`rc`) combines posted fields
from `FORM` with query string fields from `URL`.

## What a run on Adobe 2023 showed

Findings from firing the whole catalog, worth knowing before you read your own
run:

- **Query-string values are masked since 2.1.0.** An earlier run on this catalog
  found `/trigger/maskedRc` masking secrets in the Request collection section
  while the Request section above it printed `cgi.query_string` verbatim. The
  `maskQueryString` setting (on by default) now applies `maskKeys` to the query
  string row. Note that matching is exact since 2.1.0: `creditCardNumber` is
  only masked if the app lists it - the entry `creditcard` does not cover it by
  substring. The harness config lists `creditCardNumber` explicitly, which is
  why `/trigger/maskedRc` masks it; since `maskKeys` became empty by default,
  every masked name on that route comes from the harness's own opt-in list.
- **The budget-bounded sanitizer removed the large-payload cost.** The benchmark
  suite at `tests/specs/perf/PayloadBuilderBenchmarkTest.cfc`
  (`?directory=tests.specs.perf`) was run on Lucee 5.4.8 before and after the
  sanitizer rework, five runs per scenario, average shown:

  | Scenario | Before | After |
  | --- | --- | --- |
  | 5 MB string in extraInfo | 47 ms | 3 ms |
  | 20,000-key flat struct | 63 ms | 4 ms |
  | 500 KB JSON body | 30 ms | 24 ms |
  | 5 MB string with 17 maskKeys + 2 patterns | 54 ms | 1 ms |
  | 1,000 structs x 10 keys, 100 maskKeys + 10 patterns | 59 ms | 2 ms |
  | Small baseline payload | 2 ms | 2 ms |

  The JSON-body scenario keeps most of its cost because `deserializeJSON` on a
  500 KB body runs before the walk and is unavoidable. The heavy mask
  configurations now cost less than the unmasked runs did, because the walk
  stops as soon as the email's budget is full.
- **Compiling the mask configuration once per alert removed the wide-`rc` cost.**
  `ensureMaskConfig()` used to run once per `rc` key and once per header, and
  each call rebuilt a fingerprint from three list joins. Scenario (d), an `rc`
  with 100 keys, went from min 7 ms / avg 10 ms to min 2-4 ms / avg 4 ms.

  Read the numbers above as a comparison, not as absolute figures for your
  machine. Timings on a developer laptop move by a factor of three between runs
  depending on JIT warm-up and what else is running, and the 500 KB JSON
  scenario is the worst of them: it was measured at 18 ms and at 71 ms within
  the same five-run batch. Compare a before and an after taken back to back on
  one machine, in the same JVM, after two warm-up runs. Anything else is
  measuring the laptop.
- **A REST handler failure alerted twice before 2.4.0.** `/api/boom` produced two
  emails. `RestHandler.aroundHandler()` catches whatever the action throws and
  calls `onAnyOtherException()`, which logs at ERROR under the `handlers.Api`
  category and then announces `onException` on the next line, so both the
  appender and the module's interceptor captured the same exception.
  `ignoreCategories` cannot filter that log, because `RestHandler` logs under the
  calling handler's own category, which differs for every handler. Since 2.4.0
  the `suppressDuplicateFrameworkLogs` setting drops the logged copy and keeps
  the announced one, which is the only copy carrying a real `tagContext` and so
  the only one that can show a stack trace and a code snippet. `/api/boom` now
  produces one email, the same as a plain handler.
- **The `onError` path still alerts, and that is deliberate.**
  `RestHandler.onError()` logs the same `{ _stacktrace, httpData }` shape but
  announces nothing, so its log is the only report of the failure. Suppressing it
  would lose the alert. `/apiFault/boom` throws in `preHandler`, which escapes
  `aroundHandler` and reaches `onError()`, and produces one email. Note that
  `onError()` rethrows instead of logging when ColdBox `debugMode` is on.
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

A scenario that must run outside ColdBox is a file under `test-harness/legacy/`
instead of an action in the Trigger handler. Add the file, then add its path to
the legacy group on the harness home page.

## Running the specs

```bash
box run-script start:2023
```

then <http://127.0.0.1:60310/tests/runner.cfm>. Unset `ERRORALERTS_MAILER`
first — the integration specs read the in-memory mailbox, and with the SMTP
mailer active it stays empty.
