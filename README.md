# errorAlerts

![errorAlerts Logo](https://github.com/homestar9/errorAlerts/blob/main/errorAlerts-logo.avif?raw=true)

`errorAlerts` emails developers when a ColdBox application has an unhandled exception or logs an `ERROR` or `FATAL` message.

By default, the first three occurrences of one error send emails immediately. Later occurrences are counted and sent in one digest. This limit prevents a large error burst from flooding your inbox.

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

Replace both example addresses with addresses that your mail server accepts.

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

Visit the action in your browser. You should receive an email with the error details, request details, source code, stack frames, and runtime versions.

If an error starts deep inside framework or ORM code, the email also finds the first frame from your application. The email labels this frame and its source as "Application caller." A row such as "... 5 frames omitted" marks a shortened stack.

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

The module groups errors by LogBox category, the first 200 message characters, the top stack frame, and the first application stack frame. It replaces numbers and UUIDs in messages by default. For example, `Order 123 failed` and `Order 456 failed` belong to the same group.

Database errors often have the same framework frame at the top of the stack. The application frame keeps failures from different call sites in separate groups. `applicationFramePrefixes` defines which paths belong to the application.

With the defaults, if the same error occurs five times within ten minutes:

1. Occurrences 1, 2, and 3 produce immediate emails.
2. Occurrences 4 and 5 are suppressed.
3. After the ten-minute window closes, one digest reports that the error occurred two more times.

Throttle counters are stored in memory and are separate for each application server.

ColdBox's `RestHandler` can report one exception twice with different categories and messages. Throttling cannot group those two reports. The module drops the logged copy and keeps the `onException` announcement. Only the announcement has the `tagContext` needed for stack frames and source code. See `suppressDuplicateFrameworkLogs` in the advanced settings.

## Common configuration recipes

Most examples belong in the struct returned by `config/modules/errorAlerts.cfc`. Examples that add another function show the complete file.

### Disable alerts in development

Alerts are active in every environment. To disable one environment, add a function with that environment's name to `config/modules/errorAlerts.cfc`. ColdBox passes the merged settings to this function after `configure()` runs.

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

The function name must match the detected environment name. For example, use `staging( settings )` for the staging environment.

Change `settings` directly. ColdBox ignores the function's return value.

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

You may override only the nested keys you need. Module startup restores any missing `throttle` defaults.

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

Category matching ignores case and checks the start of the category. Keep the two default categories:

- `cbmailservices` prevents a failed alert email from generating another alert.
- `coldbox.system.Bootstrap` prevents duplicate emails for unhandled exceptions.

### Identify the logged-in user

Set `userProvider` to a closure that receives WireBox and returns text for the signed-in user. This example uses [cbauth](https://forgebox.io/view/cbauth):

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

Return `""` when nobody is signed in. A provider error is ignored so it cannot stop the alert. The row then uses `emptyValueText`.

### Include the request body for API endpoints

A JSON request body does not appear in `rc`. Enable request bodies when that input is needed for API errors:

```cfc
includeRequestBody : true
```

JSON objects and arrays use the masking settings at every visited level. Output stops at `requestBodyMaxLength`. Form posts stay excluded because `rc` already shows their masked fields.

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

## Masking and sanitization

Alert emails can include request data and secrets. Masking is **off by default** because each application uses different field names. Add your sensitive field names to `maskKeys` before production use.

### Exact key names: `maskKeys`

```cfc
maskKeys : [
    // A starter list to copy. Keep what applies and add your own field names.
    "password", "passwd", "token", "secret", "apikey", "api_key",
    "authorization", "creditcard", "cvv",
    "ssn", "cardNumber", "client_secret", "access_token", "refresh_token"
]
```

A matching field value becomes `*** masked ***` in `rc`, JSON bodies, `extraInfo`, and query strings. Matching ignores case but requires the complete field name. For example, `password` does **not** match `newPassword` or `passwordConfirm`. List every sensitive name used by your forms and APIs. The module uses one hash lookup per field, so a long list does not make each lookup slower.

Masking a container key, such as `auth` or `profile`, hides the entire structure under it with one entry.

### Wildcard patterns: `maskKeyPatterns`

Use a wildcard pattern when outside systems provide many versions of one field name. For example, `ssn` does not match `indemnitor1SocialSecurityNumber`. This pattern does:

```cfc
maskKeyPatterns : [ "*socialsecurity*" ]
```

`*` matches any number of characters. It is the only special character. Matching ignores case and covers the complete key. The module checks patterns only when `maskKeys` has no exact match. Pattern results are cached for repeated field names.

Keep patterns narrow. For example, `*token*` also hides useful fields such as `tokenCount` and `nextPageToken`. Version 2.1.0 removed automatic substring matching for this reason.

### Long values: `longValueMaxLength` and `longValueExemptKeys`

Payloads can contain large strings such as files or API responses. A value longer than `longValueMaxLength` keeps its beginning and adds its original size:

```text
JVBERi0xLjcKJeLjz9MKMSAwIG9iago8PC9UeXBlL0NhdGFsb2… [truncated, 245120 chars total]
```

Set `longValueMaxLength : 0` to disable the per-value limit. Keys in `longValueExemptKeys` skip this limit. The default exemptions keep stack traces readable. Complete section limits still apply.

The sanitizer stops after it collects enough content for the section limit. `extraInfo` uses `extraInfoMaxLength`, and JSON bodies use `requestBodyMaxLength`. Large structures stop early and show `[N more keys]`. Every displayed value passes the mask check before a limit can stop the walk.

### Which do I need?

| Situation | Reach for |
|---|---|
| You know the field name | `maskKeys` |
| Many vendor spellings of one field | `maskKeyPatterns` |
| A whole container with no diagnostic value | the container's key in `maskKeys` |
| Huge values bloating or slowing alerts | Nothing. `longValueMaxLength` is on by default. |

### What key masking can never reach

Key masking needs a field name. It cannot mask bound SQL values, exception `detail`, exception `extendedInfo`, non-JSON bodies, or secrets inside plain strings. Change a logging call if it passes a secret in one of these places. Length limits reduce the amount shown but do not make this content safe.

An XML or plain-text body is printed as sent, up to `requestBodyMaxLength`. A body recognized as JSON is either walked and masked or reported by size. JSON is not printed raw when parsing or masking cannot finish.

Engines do not always agree about valid JSON. Adobe ColdFusion 2023 rejects a trailing comma that Lucee 5 and BoxLang accept. An engine may treat malformed JSON as plain text and print it as sent. Keep `includeRequestBody` off when request bodies may contain secrets.

### Objects passed as `extraInfo`

The sanitizer walks plain structs and arrays. It sends a component instance directly to the JSON serializer. **Keys inside the component are not checked against `maskKeys`.** A component with a cached token may print that token.

Queries also go directly to the serializer. Their rows often provide useful details. Objects often contain framework state and can have large data graphs, so logging them is less useful and more expensive.

The fix belongs at the logging call site. Log the values you need, not the whole object:

```cfc
// This can print unmasked component data.
logger.error( "Charge failed", { gateway : paymentGateway } );

// Log plain fields so maskKeys can check them.
logger.error( "Charge failed", {
    gateway    : "AcmePay",
    statusCode : response.statusCode,
    orderId    : order.getId()
} );
```

The module does not call `getMemento()` on an object. On a Quick or cborm entity, that call can query relationships, walk an unlimited object graph, or throw another error.

The `rc` table shows an object as `[object com.foo.Bar]`. The table only supports short strings limited by `rcValueMaxLength`. This output does not mean the object's keys were masked.

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

`throttle` and `includeScopes` are structs. ColdBox replaces a complete nested struct when an application overrides one key. The module restores missing defaults during startup, so partial overrides are safe:

```cfc
moduleSettings = {
    errorAlerts : {
        to            : "dev@example.com",
        includeScopes : { session : true },   // rc, cgi and extraInfo keep their defaults
        throttle      : { windowSeconds : 60 } // maxPerWindow and maxTrackedSignatures keep theirs
    }
};
```

### Advanced settings

| Setting | Default | Description |
|---|---|---|
| `notifier` | `"EmailNotifier@errorAlerts"` | WireBox ID of the notification provider. |
| `suppressDuplicateFrameworkLogs` | `true` | Drops the LogBox copy of an exception that `RestHandler` also announces. Category rules cannot find every copy because each handler has a different category. Set this to `false` only after unregistering `UnhandledExceptionCapture`. |
| `throttle.maxTrackedSignatures` | `500` | Maximum error signatures kept in memory. New signatures send unthrottled when the limit is reached. |
| `digestFlushSeconds` | `60` | How often expired throttle windows are checked for pending digests. |
| `normalizeSignatures` | `true` | Replaces digit runs and UUIDs before errors are grouped. |
| `maxBodyBytes` | `102400` | Maximum rendered email size. Lower-priority sections are removed first. |
| `rcValueMaxLength` | `200` | Maximum rendered length of each request-collection value. |
| `stackFrames` | `10` | Maximum stack frames shown. Driver frames that are not file paths are skipped after the first frame. The first application frame is added when it falls past this limit. |
| `applicationFramePrefixes` | Conventional ColdBox folders | Paths that mark application stack frames. Defaults cover handlers, models, views, layouts, config, interceptors, and `modules_app`. Installed dependencies under `/modules/` are excluded. |
| `digestSampleSize` | `5` | Maximum distinct routes and client IP addresses listed in a digest. `0` disables both lists. A client controls `X-Forwarded-For`, so treat the IP address as a hint rather than proof. |
| `includeScopes` | `{ rc: true, cgi: true, extraInfo: true, session: false }` | Controls which diagnostic sections are included. `session` adds a `sessionId` row so alerts from one visitor can be tied together. |
| `codeSnippetLines` | `5` | Source lines shown either side of the failing line, with the failing line highlighted. `0` turns the snippet off. Costs one file read per alert and puts application source in the email. |
| `userProvider` | `""` | Closure that receives WireBox and returns text for the signed-in user. See the recipe above. The `user` row only appears when this is set. |
| `relativePaths` | `true` | Trims the application root from file paths so a path reads `/handlers/Main.cfc`. Paths outside the application root are always shown in full. Set `false` to keep every path absolute. |
| `includeQueryParams` | `true` | Include bound values from a failed query. These values can help reproduce the error, but they may contain user input that `maskKeys` cannot hide. |
| `maskQueryString` | `true` | Apply `maskKeys` and `maskKeyPatterns` to the query string shown in the Request section. Turning this off can put a secret from a GET request in email. |
| `emptyValueText` | `"N/A"` | Placeholder shown for a request value the request did not provide. |
| `includeHeaders` | `[ "Content-Type" ]` | Request headers shown in the Request section. `Cookie`, `Authorization`, and `Proxy-Authorization` are always blocked. |
| `includeRequestBody` | `false` | Include bodies that are not form posts. JSON objects and arrays are masked. JSON that cannot be walked is reported by size. Non-JSON text is shown as sent because it has no field names to mask. |
| `requestBodyMaxLength` | `4000` | Maximum characters of request body shown. |
| `maskKeys` | `[]` | Exact field names to mask in `rc`, JSON bodies, `extraInfo`, and query strings. Nested walking stops after five levels. Matching ignores case. Masking is off by default. |
| `maskKeyPatterns` | `[]` | Wildcard field-name patterns, checked only when the exact `maskKeys` lookup misses. `*` matches any run of characters; matching ignores case and covers the whole name. |
| `longValueMaxLength` | `500` | Per-value cap for string values found while walking `extraInfo` or a JSON body. Longer values keep this many characters plus a label stating the real size. `0` disables the per-value cap. |
| `longValueExemptKeys` | `[ "_stacktrace", "stacktrace" ]` | Keys whose values skip the per-value cap, matched exactly ignoring case, so stack traces keep their frames. The whole-output caps still apply. |
| `extraInfoMaxLength` | `2000` | Maximum characters of sanitized `extraInfo` shown, and the collection budget for its walk. |

Masking is opt-in and has its own section above: see [Masking and sanitization](#masking-and-sanitization) for the starter list, wildcard patterns, and long-value truncation.

### Upgrading past 2.4

Masking is now opt-in. Applications that relied on the old default list must set `maskKeys`. Copy the starter list from [Masking and sanitization](#masking-and-sanitization) and keep the names your application uses. This release also masks nested `rc` and JSON fields. Strings longer than `longValueMaxLength` now show a shortened value and size label. Set the limit to `0` to keep complete values.

### Upgrading to 2.3

Two behavior changes to know about:

- Error signatures now include the first application stack frame. Different call sites with the same message now use separate throttle windows. Existing windows restart during the upgrade and may allow up to `maxPerWindow` extra emails.
- `relativePaths` now defaults to `true`, so file paths inside the application root render as `/handlers/Main.cfc` instead of the full absolute path. Set it back to `false` to keep absolute paths.

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

The module adds an appender to ColdBox's root LogBox logger and registers an `onException` interceptor. Both use the same capture process. The process applies ignore rules, groups matching errors, throttles repeats, sanitizes the payload, and calls the notifier. Internal failures do not escape into the original request.

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

A custom notifier does not require `to`. It must handle its own failures. Do not log those failures at `ERROR` because that can create an alert loop.

## Operational notes

- Throttle counters and pending digests are lost on application restart or `fwreinit`.
- Throttling is per JVM, so web-farm nodes do not share counters.
- Queued delivery does not wait during the failing request. Delivery time depends on the cbmailservices scheduler.
- Masking is opt-in: `maskKeys` ships empty, and the exact match means every sensitive field name your application actually uses has to be listed. Review [Masking and sanitization](#masking-and-sanitization) before production use.

## Contributing

```bash
box run-script install:dependencies
box run-script start:2023
box testbox run
```

To use another engine, run its start script: `start:boxlang`, `start:lucee5`, `start:lucee6`, or `start:2025`. Prefix the script with `box run-script`. All engines use the same port, so stop the active engine first.

The harness home page at <http://127.0.0.1:60310/> lists every failure scenario. It can send alerts to a local SMTP server for inspection. See [docs/test-harness.md](docs/test-harness.md).

Releases must use `box run-script release`; do not run `box publish` directly from the repository root. See [RELEASE.md](RELEASE.md) for the routine and [docs/release-process.md](docs/release-process.md) for why.

## License

MIT
