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

- Alerts are active in every environment, including `development`.
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

Visit the action in your browser. You should receive an email containing the error message, exception details, the source lines around the failing line, the route, stack frames, and a sanitized copy of the request collection.

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

Most examples in this section go inside the struct returned by `config/modules/errorAlerts.cfc`. A few show that whole file instead, because they add a function next to `configure()`.

### Disable alerts in development

Alerts are active in every environment. To turn them off in one environment, add a function named after that environment to `config/modules/errorAlerts.cfc`. ColdBox calls it with the merged settings struct after `configure()` returns, so your changes apply only in that environment:

```cfc
component {

    function configure(){
        return {
            to   : "alerts@example.com",
            from : "errors@example.com"
        };
    }

    // ColdBox runs this only when the detected environment is `development`.
    function development( settings ){
        settings.enabled = false;
    }

}
```

The function name must match the environment name that ColdBox detects. Add a `staging( settings )` function the same way to change settings there.

Change `settings` in place. The function's return value is ignored, so `return { enabled : false }` has no effect.

If you prefer to keep all environment overrides in one file, a `development()` function in `config/Coldbox.cfc` that sets `moduleSettings.errorAlerts.enabled = false` works too.

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

### Identify the logged-in user

Set `userProvider` to a closure that receives WireBox and returns a display string. The alert's Request section then shows who was signed in when the error happened. This example uses [cbauth](https://forgebox.io/view/cbauth):

```cfc
userProvider : function( wirebox ){
    var auth = wirebox.getInstance( "AuthenticationService@cbauth" );
    if ( !auth.isLoggedIn() ) {
        return "";
    }
    var user = auth.getUser();
    return "#user.getName()# <#user.getEmailAddress()#> (id #user.getId()#)";
}
```

Return `""` when nobody is signed in. Errors thrown by the closure are swallowed so a broken provider can never stop an alert; the row simply shows the `emptyValueText` placeholder.

### Include the request body for API endpoints

A failing JSON API call shows no input by default, because the posted body never reaches `rc`. Turn the body on for API-heavy applications:

```cfc
includeRequestBody : true
```

JSON bodies get their top-level fields masked with `maskKeys` and are capped at `requestBodyMaxLength` characters. Form posts stay excluded because the `rc` table already shows those fields, masked.

### Write test emails to files

For local testing without SMTP, use synchronous delivery in `config/modules/errorAlerts.cfc`:

```cfc
component {

    function configure(){
        return {
            to           : "developer@example.com",
            from         : "errors@example.com",
            deliveryMode : "send"
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
| `stackFrames` | `10` | Maximum stack frames shown in an alert. Frames whose template is not a file path, such as JDBC driver internals, are skipped after the first frame. |
| `includeScopes` | `{ rc: true, cgi: true, extraInfo: true, session: false }` | Controls which diagnostic sections are included. `session` adds a `sessionId` row so alerts from one visitor can be tied together. |
| `codeSnippetLines` | `5` | Source lines shown either side of the failing line, with the failing line highlighted. `0` turns the snippet off. Costs one file read per alert and puts application source in the email. |
| `userProvider` | `""` | A closure that receives WireBox and returns a display string for the signed-in user. See the recipe below. The `user` row only appears when this is set. |
| `relativePaths` | `false` | When `true`, trims the application root from file paths so a path reads `/handlers/Main.cfc`. |
| `includeQueryParams` | `true` | Include the bound parameter values from a failed query. The best data for reproducing a database error, but the values can contain whatever a visitor typed, and `maskKeys` cannot filter them because they carry no field names. |
| `maskQueryString` | `true` | Apply `maskKeys` to the query string shown in the Request section. Turning this off can put a secret from a GET request in email. |
| `emptyValueText` | `"N/A"` | Placeholder shown for a request value the request did not provide. |
| `includeHeaders` | `[ "Content-Type" ]` | Request headers shown in the Request section, matched ignoring case. `Cookie` and `Authorization` are never included, even when listed. |
| `includeRequestBody` | `false` | Include the raw request body. Useful for JSON and API endpoints, whose payload never reaches `rc`. JSON bodies get their top-level fields masked with `maskKeys`; form posts are skipped because `rc` already shows them masked. |
| `requestBodyMaxLength` | `4000` | Maximum characters of request body shown. |
| `maskKeys` | Password/token-related names | Request keys and query-string fields whose values are replaced with `*** masked ***`. Matching is exact, ignoring case. |

The default `maskKeys` list covers `password`, `passwd`, `token`, `secret`, `apikey`, `api_key`, `authorization`, `creditcard`, and `cvv`. Matching is an exact, case-insensitive comparison: `password` does **not** cover `newPassword` or `passwordConfirm`. Check the real field names your forms post and list every variant before using alerts in production.

### Upgrading from 2.0

`maskKeys` matching changed from substring to exact in 2.1.0. A key such as `apiToken`, which the `token` entry used to mask by substring, is no longer masked unless you list it explicitly. Before upgrading, audit your forms and add every sensitive field name to `maskKeys` in `config/modules/errorAlerts.cfc`.

## Troubleshooting

### No email arrives

Check these items in order:

1. Confirm that `to` is not blank and `enabled` is still `true`.
2. Check `config/modules/errorAlerts.cfc` and `config/Coldbox.cfc` for an environment function that turns `enabled` off for the current environment.
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
- Request values are truncated and keys named in `maskKeys` are masked, but the match is exact: review `maskKeys` and list every sensitive field name your application actually uses.

## Contributing

```bash
box run-script install:dependencies
box run-script start:2023
box testbox run
```

To run the harness on another engine, swap the start script: `box run-script start:boxlang` (BoxLang), `box run-script start:lucee5` (Lucee 5), `box run-script start:lucee6` (Lucee 6), or `box run-script start:2025` (Adobe 2025). All engines use the same port, so stop one before starting another.

The harness home page at <http://127.0.0.1:60310/> lists every failure scenario the module can be tested against, and can send the resulting alerts to a local SMTP server so you can read them as real email. See [docs/test-harness.md](docs/test-harness.md).

Releases must use `box run-script publish:release`; do not run `box publish` directly from the repository root.

## License

MIT
