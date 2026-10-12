# errorAlerts

![errorAlerts Logo](https://github.com/homestar9/errorAlerts/blob/main/errorAlerts-logo.avif?raw=true)

`errorAlerts` emails developers when a ColdBox application has an unhandled
exception or logs an `ERROR` or `FATAL` message. Alerts include error details,
request data, source code, stack frames, and runtime versions when available.

By default, the first three occurrences of a matching error produce separate
alerts within ten minutes. Further occurrences appear in one summary email,
called a digest, after that time window ends. Email delivery runs in the
background, so messages may not arrive right away.

The module registers itself with ColdBox. You do not need to change the
configuration for LogBox, ColdBox's logging system.

## Requirements

- ColdBox 7 or newer (developed and tested with ColdBox 8)
- Adobe ColdFusion 2023 or 2025, Lucee 5 or 6, or BoxLang 1 or newer
- [CommandBox](https://www.ortussolutions.com/products/commandbox) for installation
- A working mail server configured in your CFML engine

[cbmailservices](https://forgebox.io/view/cbmailservices) installs automatically.
Its default mailer uses your engine's SMTP settings. If your application already
configures cbmailservices, errorAlerts uses its default mailer.

## Install and configure

### 1. Install the module

Run this command from your ColdBox application's root folder:

```bash
box install erroralerts
```

### 2. Set the email addresses and masking rules

Create `config/modules/errorAlerts.cfc`:

```cfc
component {

    function configure(){
        return {
            to            : "developer@example.com",
            from          : "errors@example.com",
            subjectPrefix : "[My App]",
            maskKeys      : [ "password", "token", "apiKey" ]
        };
    }

}
```

Replace the addresses with addresses your mail server accepts. `to` is required
for email alerts. If `from` is blank, the module uses `to` as the sender.

**Masking is off by default.** The example enables it for three field names.
Add every sensitive field name your application uses before sending real request
data in alerts. Matching ignores case but requires the full name: `password`
does not match `newPassword` or `passwordConfirm`.

Matching values become `*** masked ***` in the request collection (`rc`, which
includes form and URL fields), JSON request bodies, logged `extraInfo`, and query
strings. See the [masking guide](docs/reference.md#masking-and-request-data) for
limits and patterns.

Alerts are enabled in every environment, including development. Restart the
application or reinitialize ColdBox with `?fwreinit=true` after changing settings.

### 3. Verify delivery

Add this temporary action to an existing ColdBox handler:

```cfc
function testError( event, rc, prc ){
    throw(
        type    = "MyApp.TestError",
        message = "Testing errorAlerts"
    );
}
```

Visit the action in your browser. For example, if you added it to
`handlers/Main.cfc`, open `index.cfm?event=Main.testError`. You should receive an
alert containing the test error. Allow time for queued delivery.

Remove the action after confirming delivery. If no email arrives, use the
[checklist below](#no-email-arrived).

## Use the module

### Unhandled exceptions

Exceptions that reach ColdBox's exception handler are reported automatically.
You do not need to add reporting code to each handler.

### Errors your application catches

To report a caught error, inject a LogBox logger and log at `ERROR` or `FATAL`.
For example, add a method like this to a component created by WireBox, such as
a handler or service:

```cfc
component {

    property name="log" inject="logbox:logger:{this}";

    function reportError( required any exception ){
        log.error(
            message   = "Order could not be saved",
            extraInfo = arguments.exception
        );
    }

}
```

Call `reportError( exception )` from your catch block and choose a message that
describes the failed operation. `extraInfo` carries the caught exception so the
alert can include its type, detail, and stack frames.

### Pages outside ColdBox

For pages that run outside ColdBox, use the
[`Application.cfc` example](docs/reference.md#pages-outside-coldbox).

## Common settings

Set these values in the struct returned by `configure()` in
`config/modules/errorAlerts.cfc`.

| Setting | Default | Purpose |
|---|---|---|
| `to` | `""` | Recipient address. Required for email alerts. |
| `from` | `""` | Sender address. Uses `to` when blank. |
| `subjectPrefix` | `""` | Text before the subject. Uses the app name when blank. |
| `enabled` | `true` | Set to `false` to stop alerts. |
| `deliveryMode` | `"queue"` | `"queue"` sends later; `"send"` waits for delivery. |
| `maskKeys` | `[]` | Full field names whose values should be hidden. |
| `throttle.maxPerWindow` | `3` | Separate alerts allowed per matching error in a time window. |
| `throttle.windowSeconds` | `600` | Length of that time window in seconds. |

See the [complete settings reference](docs/reference.md#settings) for other options.

### Disable alerts in development

Add this function inside the same configuration component, after `configure()`:

```cfc
function development( settings ){
    settings.enabled = false;
}
```

ColdBox calls it when the detected environment is `development`. Use the matching
environment name for another environment, such as `staging`. Change `settings`
directly; ColdBox ignores the function's return value.

### Change the alert limit

Add this entry to the struct returned by `configure()` to allow one separate
alert per matching error in five minutes:

```cfc
throttle : {
    maxPerWindow  : 1,
    windowSeconds : 300
}
```

Further occurrences still appear in a digest. You can override only the nested
keys you need; missing throttle settings keep their defaults.

### Check what your alerts include

Masking does not remove secrets from plain text, SQL parameter values, or fields
inside objects and queries. Log only the data you need. Request bodies are off by
default; non-JSON bodies can appear as sent if you enable them. Review the
[masking limits](docs/reference.md#what-masking-does-not-hide) before including
sensitive data.

## No email arrived

Check these items in order:

1. Set `to` and confirm `enabled` is `true`, including any environment override.
2. Restart or reinitialize ColdBox so your latest settings load.
3. Trigger an unhandled exception or log at `ERROR` or `FATAL`. Logged `WARN`
   messages are excluded by default.
4. Confirm your engine or configured cbmailservices mailer can send a normal email.
5. Check the server console and error logs for messages beginning with `errorAlerts`.

Email is queued by default. Repeated errors may wait for a digest instead of
producing another separate email. See [troubleshooting](docs/reference.md#troubleshooting)
for delivery delays, ignored errors, and missing digests.

## Further help

- [Reference guide](docs/reference.md): all settings, more examples, and troubleshooting.
- [Changelog](CHANGELOG.md): changes and release history.
- [Issue tracker](https://github.com/homestar9/errorAlerts/issues): report a problem.

## License

MIT
