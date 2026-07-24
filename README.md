# errorAlerts

`errorAlerts` emails you when a ColdBox application has an unhandled exception or logs an `ERROR` or `FATAL` message.

It is designed to be safe during an error storm. By default, the first three occurrences of the same error are emailed immediately. Additional occurrences are counted and sent later in one digest instead of flooding your inbox.

The module registers itself with ColdBox, so you do not need to edit your LogBox configuration.

## Requirements

- ColdBox 7 or newer (developed and tested with ColdBox 8)
- Adobe ColdFusion 2023 or 2025, Lucee 5 or 6, or BoxLang 1 or newer
- [CommandBox](https://www.ortussolutions.com/products/commandbox) for installation
- A working mail server configured in your CFML engine

`errorAlerts` sends mail through [cbmailservices](https://forgebox.io/view/cbmailservices), which is installed automatically. Its default `CFMail` protocol uses the SMTP settings from your Adobe ColdFusion Administrator, Lucee Administrator, or BoxLang configuration.

## Quick start

### 1. Install the module

Run this command from your ColdBox application's root folder:

```bash
box install erroralerts
```

### 2. Configure the recipient

Create `config/modules/errorAlerts.cfc` in your application:

```cfc
component {

    function configure(){
        return {
            to            : "developer@example.com",
            from          : "errors@example.com",
            subjectPrefix : "[My App]"
        };
    }

}
```

Replace the example addresses with real addresses that your mail server is allowed to use.

Important defaults:

- Alerts are disabled in the `development` environment unless you explicitly enable them.
- The built-in email notifier stays inactive when `to` is blank.
- Only `ERROR` and `FATAL` messages produce alerts.
- Email is queued by default, so it may not appear immediately.

Restart or reinitialize your ColdBox application after adding or changing the configuration.

### 3. Test the installation

Add a temporary action to one of your ColdBox handlers:

```cfc
function testError( event, rc, prc ){
    throw(
        type    = "MyApp.TestError",
        message = "Testing errorAlerts"
    );
}
```

Visit the action in your browser. In a non-development environment, you should receive an email containing the error message, exception details, route, stack frames, and a sanitized copy of the request collection.

Remove the test action after confirming delivery.

## Using errorAlerts

### Unhandled exceptions

No extra code is required. Exceptions that reach ColdBox's exception handler are captured automatically:

```cfc
function saveOrder( event, rc, prc ){
    // If this throws and is not caught, errorAlerts sends an alert.
    orderService.save( rc );
}
```

### Logged errors

You can also send alerts for errors that your application catches. Inject a LogBox logger and log at `ERROR` or `FATAL`:

```cfc
component {

    property name="log" inject="logbox:logger:{this}";

    function chargeCard( required struct payment ){
        try {
            return paymentService.charge( arguments.payment );
        } catch ( any exception ) {
            log.error(
                message   = "Card charge failed",
                extraInfo = exception
            );
            rethrow;
        }
    }

}
```

Passing the caught exception as `extraInfo` lets the alert include its type, detail, and stack frames.

## How throttling works

Errors are grouped using their LogBox category, message, and top stack frame. Numbers and UUIDs in messages are normalized by default, so messages such as `Order 123 failed` and `Order 456 failed` are treated as the same error.

With the defaults, if the same error occurs five times within ten minutes:

1. Occurrences 1, 2, and 3 produce immediate emails.
2. Occurrences 4 and 5 are suppressed.
3. After the ten-minute window closes, one digest reports that the error occurred two more times.

Throttle counters are stored in memory and are separate for each application server.

## Common configuration recipes

All examples in this section go inside the struct returned by `config/modules/errorAlerts.cfc`.

### Enable alerts during development

Setting `environments` creates an explicit allow-list:

```cfc
environments : [ "development", "staging", "production" ]
```

Use this while testing, but avoid sending repeated development errors to a shared production inbox.

### Include WARN messages

```cfc
levelMin : "FATAL",
levelMax : "WARN"
```

Valid LogBox levels are `OFF`, `FATAL`, `ERROR`, `WARN`, `INFO`, and `DEBUG`.

### Change the throttle

This example sends one immediate email per matching error every five minutes:

```cfc
throttle : {
    maxPerWindow         : 1,
    windowSeconds        : 300,
    maxTrackedSignatures : 500
}
```

When overriding a nested setting such as `throttle`, include every key in that struct.

### Ignore expected errors or noisy categories

```cfc
ignoreExceptionTypes : [
    "EventHandlerNotRegisteredException",
    "MyApp.ExpectedException"
],
ignoreCategories : [
    "cbmailservices",
    "coldbox.system.Bootstrap",
    "coldbox.system.web.services.HandlerService",
    "myapp.healthcheck"
]
```

Category matching is case-insensitive and checks the beginning of the category. Keep the two default categories shown above:

- `cbmailservices` prevents a failed alert email from generating another alert.
- `coldbox.system.Bootstrap` prevents duplicate emails for unhandled exceptions.

### Write test emails to files

For local testing without SMTP, first enable the development environment in `config/modules/errorAlerts.cfc` and use synchronous delivery:

```cfc
component {

    function configure(){
        return {
            to            : "developer@example.com",
            from          : "errors@example.com",
            environments  : [ "development" ],
            deliveryMode  : "send"
        };
    }

}
```

Then create `config/modules/cbmailservices.cfc`:

```cfc
component {

    function configure(){
        return {
            defaultProtocol : "default",
            mailers : {
                "default" : {
                    class      : "File",
                    properties : {
                        filePath : "/mail-spool"
                    }
                }
            }
        };
    }

}
```

Trigger a test error, then open the generated HTML file in the application's `mail-spool` folder. Do not use the File protocol as your production mailer.

## Configuration reference

### Common settings

| Setting | Default | Description |
|---|---|---|
| `enabled` | `true` | Master switch for all alerts. |
| `environments` | `[]` | Allowed ColdBox environments. Empty means every environment except `development`. |
| `to` | `""` | Alert recipient. Required by the built-in email notifier. |
| `from` | `""` | Sender address. Uses `to` when blank. |
| `subjectPrefix` | `""` | Text added to subjects. Uses the ColdBox application name when blank. |
| `deliveryMode` | `"queue"` | `"queue"` sends in the background; `"send"` sends synchronously. |
| `levelMin` | `"FATAL"` | Lowest numeric end of the LogBox severity range. |
| `levelMax` | `"ERROR"` | Highest numeric end of the LogBox severity range. Set to `"WARN"` to include warnings. |
| `throttle.maxPerWindow` | `3` | Immediate emails allowed for one error signature per window. |
| `throttle.windowSeconds` | `600` | Length of the fixed throttle window. |
| `ignoreCategories` | See below | Category prefixes that never produce alerts. |
| `ignoreExceptionTypes` | `[]` | Exception types that never produce alerts. |

The default ignored categories are `[ "cbmailservices", "coldbox.system.Bootstrap" ]`.

### Advanced settings

| Setting | Default | Description |
|---|---|---|
| `notifier` | `"EmailNotifier@errorAlerts"` | WireBox ID of the notification provider. |
| `throttle.maxTrackedSignatures` | `500` | Maximum error signatures kept in memory. New signatures send unthrottled when the limit is reached. |
| `digestFlushSeconds` | `60` | How often expired throttle windows are checked for pending digests. |
| `normalizeSignatures` | `true` | Replaces digit runs and UUIDs before errors are grouped. |
| `maxBodyBytes` | `102400` | Maximum rendered email size. Lower-priority sections are removed first. |
| `rcValueMaxLength` | `200` | Maximum rendered length of each request-collection value. |
| `stackFrames` | `10` | Maximum stack frames shown in an alert. |
| `includeScopes` | `{ rc: true, cgi: true, extraInfo: true }` | Controls which diagnostic sections are included. |
| `maskKeys` | Password/token-related names | Request keys whose values are replaced with `*** masked ***`. Matching is by substring. |

The default `maskKeys` list covers `password`, `passwd`, `token`, `secret`, `apikey`, `api_key`, `authorization`, `creditcard`, and `cvv`. Add any application-specific secret names before using alerts in production.

## Troubleshooting

### No email arrives

Check these items in order:

1. Confirm the current ColdBox environment. Development is excluded by default.
2. Confirm that `to` is not blank and `enabled` is still `true`.
3. Trigger an unhandled exception or log at `ERROR` or `FATAL`. `WARN` and lower levels are ignored by default.
4. Reinitialize ColdBox so the module reloads your settings.
5. Confirm that your engine can send a normal email through its configured SMTP server.
6. Temporarily set `deliveryMode : "send"` to remove the background queue delay.
7. Check your server console or standard-error log for a message beginning with `errorAlerts`.
8. Confirm the error's category or exception type is not on an ignore list.

Mail delivery failures are intentionally prevented from breaking the original request. They are written to standard error instead of being thrown back into your application.

### The first email arrives, but later ones do not

This is usually throttling. The first three matching errors send immediately; the rest appear in a digest after the window closes.

### Alerts appear more than three times

Throttle state is kept per JVM. In a web farm, each server can send up to `maxPerWindow` immediate alerts. Restarting the application or running `fwreinit` also resets the counters.

### A digest never arrives

Pending throttle data lives only in memory. Restarting or reinitializing the application before the window is flushed discards the pending digest.

## How it works

The module attaches an appender to ColdBox's root LogBox logger and registers an `onException` interceptor. Both feed the same capture pipeline, which applies ignore rules, groups matching errors, throttles repeats, builds a sanitized payload, and passes it to the configured notifier. Internal failures are contained so the alerting system does not make an already-failing request worse.

## Custom notifiers

To deliver alerts somewhere other than email, create a singleton that implements the notifier interface:

```cfc
component singleton implements="errorAlerts.models.notifiers.INotifier" {

    void function sendNotification( required struct payload ){
        try {
            // Send payload to your alert service.
            // payload.type is either "error" or "digest".
        } catch ( any exception ) {
            // A notifier must not throw into the original request.
        }
    }

}
```

Map the component in WireBox, then set its mapping ID:

```cfc
notifier : "MyNotifier@myapp"
```

A custom notifier does not require `to`. It must contain its own failures and must not log them at `ERROR`, which could create an alert loop.

## Operational notes

- Throttle counters and pending digests are lost on application restart or `fwreinit`.
- Throttling is per JVM, so web-farm nodes do not share counters.
- The default queued delivery avoids blocking the failing request, but delivery timing depends on the cbmailservices scheduler.
- Request values are truncated and common secret-looking keys are masked, but you should review `maskKeys` for your application.

## Contributing

```bash
box run-script install:dependencies
box run-script start:2023
box testbox run
```

To run the harness on another engine, swap the start script: `box run-script start:boxlang` (BoxLang), `box run-script start:lucee5` (Lucee 5), `box run-script start:lucee6` (Lucee 6), or `box run-script start:2025` (Adobe 2025). All engines use the same port, so stop one before starting another.

Releases must use `box run-script release`; do not run `box publish` directly from the repository root.

## License

MIT
