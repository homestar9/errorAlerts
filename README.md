# errorAlerts

Throttled error notifications for ColdBox apps. Install the module, tell it where to send email, and every unhandled exception and `logger.error()` call in production lands in your inbox — clean, compact, and throttled so an error storm sends a handful of emails plus one digest instead of a hundred.

## What it does

- **Self-registers a LogBox appender** on your root logger at module load. You never touch your `logBox` config struct.
- **Captures unhandled exceptions** through an `onException` interceptor. This matters because when your app defines its own `exceptionHandler` setting, ColdBox never logs the exception through LogBox — an appender alone would miss every crash.
- **Throttles by error signature**: the first 3 occurrences of the same error email immediately; the rest are counted and summarized in one digest email when the 10-minute window closes ("fired 97 more times"). Signatures normalize digits and UUIDs, so `Order 123 failed` and `Order 456 failed` count as the same error.
- **Renders Gmail-safe HTML**: nested tables and inline styles only, no `writeDump()`. Emails show the message, exception type, top stack frames, the ColdBox event/route, a sanitized `rc` (values truncated, secret-looking keys masked), and a useful CGI subset. Hard size cap of 100 KB.
- **Delivers via [cbmailservices](https://forgebox.io/view/cbmailservices)**, queued by default so SMTP never blocks the failing request.
- **Swappable delivery**: `settings.notifier` accepts any WireBox ID implementing `INotifier`, so email can be replaced with Sentry or anything else without touching the capture pipeline.

## Requirements

- ColdBox 7+ (developed against ColdBox 8)
- Adobe ColdFusion 2023+ or BoxLang
- A working mail server for the default CFMail protocol (set in the CF Administrator), or any other cbmailservices protocol

## Installation

```bash
box install erroralerts
```

Then create `config/modules/errorAlerts.cfc` in your app:

```cfc
component {

    function configure(){
        return {
            to            : "you@example.com",
            from          : "errors@yoursite.com",
            subjectPrefix : "[MySite]"
        };
    }

}
```

That is the whole integration. The module skips the `development` environment by default and refuses to activate (with one startup warning) if `to` is blank.

## Settings

| Setting | Default | What it does |
|---|---|---|
| `enabled` | `true` | Master switch. `false` loads the module but registers nothing. |
| `environments` | `[]` | Allow-list of ColdBox environments. Empty = everything **except** `development`. |
| `to` | `""` | Recipient address. Required for the shipped EmailNotifier. |
| `from` | `""` | Sender address. Falls back to `to`. |
| `subjectPrefix` | `""` | Prepended to every subject. Blank = `[<appName>]`. |
| `notifier` | `EmailNotifier@errorAlerts` | WireBox ID of the delivery object (the Sentry seam). |
| `deliveryMode` | `queue` | `queue` = cbmailservices queue task (off-request). `send` = synchronous. |
| `levelMin` / `levelMax` | `FATAL` / `ERROR` | Severity range. Set `levelMax : "WARN"` to get warning emails too. |
| `throttle.maxPerWindow` | `3` | Immediate emails per signature per window. |
| `throttle.windowSeconds` | `600` | Window length, anchored at the signature's first occurrence. |
| `throttle.maxTrackedSignatures` | `500` | Memory cap. At the cap, new signatures send untracked (fail open). |
| `digestFlushSeconds` | `60` | How often the scheduled task sweeps expired windows for digests. |
| `ignoreCategories` | `[ "cbmailservices", "coldbox.system.Bootstrap" ]` | Category prefixes that never alert. See below before changing. |
| `ignoreExceptionTypes` | `[]` | Exception `type` values that never alert, e.g. `"EventHandlerNotRegisteredException"`. |
| `normalizeSignatures` | `true` | Fold digit runs and UUIDs before hashing. |
| `maxBodyBytes` | `102400` | Hard cap on email size; lower-priority sections drop first. |
| `rcValueMaxLength` | `200` | Per-value truncation for rc. |
| `stackFrames` | `10` | Stack frames shown in the email. |
| `includeScopes` | `{ rc, cgi, extraInfo : true }` | Toggle payload sections. |
| `maskKeys` | password, token, secret, ... | rc keys (substring match) rendered as `*** masked ***`. |

### About the default ignoreCategories

- `cbmailservices` is ignored so a failing **alert email** can never alert about itself (the queue task logs send failures at ERROR).
- `coldbox.system.Bootstrap` is ignored because unhandled exceptions already arrive through the module's `onException` interceptor. Without this ignore, apps with **no** custom `exceptionHandler` would get every crash twice.
- A common addition: `"coldbox.system.web.services.HandlerService"` silences invalid-event/bot-scan noise.

## How the pieces fit

```
logger.error() ─────────► ErrorAlertAppender ─┐
                                              ├─► CaptureService ─► SignatureService (hash)
unhandled exception ─► UnhandledException ────┘        │
                        Capture (interceptor)          ▼
                                               ThrottleService (first N + digest)
                                                       │ SEND / digest
                                                       ▼
                                               PayloadBuilder ─► INotifier
                                                                    └─ EmailNotifier ─► EmailRenderer + cbmailservices
```

Every stage swallows its own failures to `System.err`. Nothing in the pipeline can throw into the failing request, and nothing logs at ERROR through LogBox (that would loop straight back into the appender).

## Custom notifiers (the Sentry seam)

Implement the interface, map it in WireBox, and point the setting at it:

```cfc
component singleton implements="errorAlerts.models.notifiers.INotifier" {

    /**
     * Receives payload structs: type "error" (severity, message, exception,
     * request, rc, signature, occurrence...) or "digest" (counts, firstSeen,
     * lastSeen...). Must swallow its own failures.
     */
    void function sendNotification( required struct payload ){
        // ship it anywhere
    }

}
```

```cfc
// config/modules/errorAlerts.cfc
return { notifier : "MySentryNotifier@myapp" };
```

## Things to know

- **Restarts reset the throttle.** Counters live in memory, so after a restart or `fwreinit` the first N of every signature email again, and a digest pending at restart is lost.
- **Web farms multiply N.** Counters are per JVM. Two instances means up to 2× `maxPerWindow` emails per error.
- **SMTP is server-level for CFMail.** The default cbmailservices protocol uses the mail server from the CF Administrator / BoxLang config. Nothing in this module configures SMTP.

## Local smoke test

1. Allow your dev environment: `environments : [ "development" ]` in the settings override, and point the CF admin mail server at [Papercut](https://github.com/ChangemakerStudios/Papercut-SMTP)/smtp4dev — or switch cbmailservices to `{ class : "File" }` and watch the spool folder.
2. Throw the same error 5 times fast (`throw( type = "Smoke", message = "errorAlerts smoke test" );` in any handler).
3. Expect 3 alert emails now and 1 digest within `digestFlushSeconds` after the window closes.

## Development

```bash
box run-script install:dependencies   # module deps + harness deps
box run-script start:2023             # harness on http://127.0.0.1:60310
box testbox run                       # full suite
```

Release with `box run-script release` — never a bare `box publish` from the repo root. CommandBox honors `.gitignore` when packaging, so an unanchored ignore pattern silently strips source from the zip; the build packages from `.tmp/` and verifies the zip's file count instead.

## License

MIT
