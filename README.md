# errorAlerts

![errorAlerts Logo](https://github.com/homestar9/errorAlerts/blob/main/errorAlerts-logo.avif?raw=true)

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

Visit the action in your browser. You should receive an email containing the error message, exception details, the source lines around the failing line, the route, a copyable request URL, stack frames, engine and framework versions, and a sanitized copy of the request collection.

When an error is thrown deep inside framework or ORM code, the email also pins the first stack frame that belongs to your own application - your handler, model, or view - and shows a second source snippet at that line, labeled "Application caller". Rows such as "... 5 frames omitted" mark where the stack list is shortened.

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

Errors are grouped using four things: their LogBox category, the first 200 characters of the message, the top stack frame, and the first stack frame that belongs to your own application. Numbers and UUIDs in messages are normalized by default, so messages such as `Order 123 failed` and `Order 456 failed` are treated as the same error.

The application frame matters most for database errors. Their top frame is always the same framework file, so without the application frame two unrelated failing queries would differ only by message text and would share one throttle window. Which folders count as application code is controlled by `applicationFramePrefixes`.

With the defaults, if the same error occurs five times within ten minutes:

1. Occurrences 1, 2, and 3 produce immediate emails.
2. Occurrences 4 and 5 are suppressed.
3. After the ten-minute window closes, one digest reports that the error occurred two more times.

Throttle counters are stored in memory and are separate for each application server.

Throttling cannot merge two reports of the same exception when they arrive with different categories and messages. That is why ColdBox's `RestHandler` needs its own handling rather than a throttle rule: it logs an exception under the calling handler's category and then announces `onException` on the next line, and the two copies hash to different signatures. The module drops the logged copy and keeps the announced one, because only the announced copy carries a real `tagContext` and is therefore the only one that can show a stack trace and a code snippet. See `suppressDuplicateFrameworkLogs` in the advanced settings.

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

JSON bodies, objects and arrays alike, get their fields masked at any depth with the masking configuration and are capped at `requestBodyMaxLength` characters. Form posts stay excluded because the `rc` table already shows those fields, masked.

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

Alert emails print request data, and request data can contain secrets. The module ships with **masking off**: `maskKeys` is empty, because only the application owner knows which field names carry secrets. Opt in by listing the real field names your application receives.

### Exact key names: `maskKeys`

```cfc
maskKeys : [
    // A starter list to copy. Keep what applies and add your own field names.
    "password", "passwd", "token", "secret", "apikey", "api_key",
    "authorization", "creditcard", "cvv",
    "ssn", "cardNumber", "client_secret", "access_token", "refresh_token"
]
```

Wherever a listed name appears — an `rc` key at any depth, a JSON request body field at any depth, an `extraInfo` key at any depth, or a query-string field name — its value is replaced with `*** masked ***`. Matching is exact apart from case: `password` does **not** cover `newPassword` or `passwordConfirm`, so list every variant your forms and APIs actually use. A long list costs nothing at alert time; the lookup is one hash check per field regardless of length.

Masking a container key, such as `auth` or `profile`, hides the entire structure under it with one entry.

### Wildcard patterns: `maskKeyPatterns`

Vendor payloads spell fields their own way. A carrier might send `indemnitor1SocialSecurityNumber`, which an `ssn` entry can never match exactly. Instead of listing twenty spellings, add one pattern:

```cfc
maskKeyPatterns : [ "*socialsecurity*" ]
```

`*` matches any run of characters and is the only special character. Matching ignores case and covers the whole key name, so a pattern without `*` behaves exactly like a `maskKeys` entry. Patterns are checked only when the exact lookup misses, and each key name's verdict is remembered for the rest of the walk, so patterns stay cheap even against an array of a thousand structs.

Keep patterns narrow. A broad pattern such as `*token*` hides fields nobody asked to hide — `tokenCount`, `nextPageToken` — which is the exact problem that made the module drop substring matching in 2.1.0.

### Long values: `longValueMaxLength` and `longValueExemptKeys`

Payloads sometimes carry huge strings: a base64-encoded PDF, a raw API response, a serialized report. By default any string value longer than `longValueMaxLength` (500) keeps its first 500 characters plus a label stating its real size:

```text
JVBERi0xLjcKJeLjz9MKMSAwIG9iago8PC9UeXBlL0NhdGFsb2… [truncated, 245120 chars total]
```

Set `longValueMaxLength : 0` to turn the per-value cap off. Keys named in `longValueExemptKeys` (default `_stacktrace` and `stacktrace`) skip the per-value cap so stack traces keep their frames; the whole-output caps still apply.

This is also what keeps alert building fast. The sanitizer stops collecting once it has enough content to fill the email — `extraInfoMaxLength` (2,000) characters for `extraInfo`, `requestBodyMaxLength` for a JSON body — so a multi-megabyte payload is never copied or serialized in full. A very wide structure stops early and reports `[N more keys]` in place of the rest. A cutoff can only leave content out; every value that reaches the email has been through the mask check first.

### Which do I need?

| Situation | Reach for |
|---|---|
| You know the field name | `maskKeys` |
| Many vendor spellings of one field | `maskKeyPatterns` |
| A whole container with no diagnostic value | the container's key in `maskKeys` |
| Huge values bloating or slowing alerts | nothing — on by default through `longValueMaxLength` |

### What key masking can never reach

Some content carries no field name to match against: the bound query parameter values shown by `includeQueryParams`, an exception's `detail` and `extendedInfo`, a request body that is not JSON, and secrets embedded inside plain string values, such as an OAuth token inside a JSON string a gateway stored in one field. Key masking cannot see into any of those. Do not put secrets in them; where a logging call site passes such a value, change the call site. Long-value truncation clips huge strings by default, which narrows this exposure but does not close it.

The non-JSON body is the one worth spelling out, because `includeRequestBody` exists to show it. An XML or plain-text body has no field names, so it is printed as sent, up to `requestBodyMaxLength`. A body the engine recognizes as JSON is different: it is always either walked and masked, or reported by size. It is never printed raw, not when it is too large to parse safely, not when parsing fails, and not when it turns out to be a bare string or number.

"Recognizes as JSON" is doing real work in that sentence. Engines disagree about what counts: Adobe ColdFusion 2023 rejects a trailing comma that Lucee 5 and BoxLang both accept. Malformed JSON is therefore treated as a plain-text body on some engines and printed as sent. If your endpoints receive secrets in the body, `includeRequestBody` is the setting to leave off.

### Objects passed as `extraInfo`

The sanitizer opens two kinds of containers: plain structs and arrays. A component instance is neither, so it is handed to the JSON serializer exactly as received. Its internal data is printed, and **no key inside it is checked against `maskKeys`**, because the sanitizer never opened it. A gateway component holding a cached token in its variables scope would print that token.

Queries behave the same way and that is usually what you want, since the rows are the diagnostic. Objects are less useful: what you get is often framework plumbing rather than your data, and an object with a very large internal graph makes the serializer work hard before the email is even assembled.

The fix belongs at the logging call site. Log the values you need, not the whole object:

```cfc
// Prints the component's internals, unmasked.
logger.error( "Charge failed", { gateway : paymentGateway } );

// Prints what you actually want to read, and maskKeys applies.
logger.error( "Charge failed", {
    gateway    : "AcmePay",
    statusCode : response.statusCode,
    orderId    : order.getId()
} );
```

The module deliberately never calls `getMemento()` to get a tidier view of an object. On a Quick or cborm entity, that method can run database queries through its relationships, recurse an object graph with no depth limit, and throw. None of those belong inside error handling.

The `rc` table is the one place that differs: it shows `[object com.foo.Bar]` instead of the contents, because that table renders short strings capped at `rcValueMaxLength`. That is a rendering limit, not a masking decision.

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

Two settings are structs rather than simple values: `throttle` and `includeScopes`. ColdBox merges module settings one level deep, so writing `includeScopes : { session : true }` replaces the whole struct instead of adding to it. The module puts the missing keys back at startup, so you can override one key and leave the rest alone:

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
| `suppressDuplicateFrameworkLogs` | `true` | Drops the LogBox copy of an exception that ColdBox's `RestHandler` both logs and announces, so a REST application receives one alert instead of two. `ignoreCategories` cannot do this, because `RestHandler` logs under the calling handler's own category, which differs for every handler. Set `false` only if you have unregistered the module's `UnhandledExceptionCapture` interceptor, since that interceptor is what reports the kept copy. |
| `throttle.maxTrackedSignatures` | `500` | Maximum error signatures kept in memory. New signatures send unthrottled when the limit is reached. |
| `digestFlushSeconds` | `60` | How often expired throttle windows are checked for pending digests. |
| `normalizeSignatures` | `true` | Replaces digit runs and UUIDs before errors are grouped. |
| `maxBodyBytes` | `102400` | Maximum rendered email size. Lower-priority sections are removed first. |
| `rcValueMaxLength` | `200` | Maximum rendered length of each request-collection value. |
| `stackFrames` | `10` | Maximum stack frames shown in an alert. Frames whose template is not a file path, such as JDBC driver internals, are skipped after the first frame. When the first application-owned frame falls past this cap, it is appended as one extra pinned frame. |
| `applicationFramePrefixes` | Conventional ColdBox folders | Path prefixes, relative to the application root, that mark a stack frame as application code. Defaults to `/handlers/`, `/models/`, `/views/`, `/layouts/`, `/config/`, `/interceptors/`, and `/modules_app/`. `/modules/` is deliberately excluded because installed dependencies live there. Override for a non-conventional source layout. |
| `digestSampleSize` | `5` | Distinct routes and client IPs a digest email lists from the occurrences in one throttle window. Values past the cap are reported as "at least N distinct". `0` turns sampling off. The client IP row puts visitor IP addresses in the email, and its value is read from the `X-Forwarded-For` request header when present, which the caller controls. Treat it as a diagnostic hint, not as proof of who sent the request. |
| `includeScopes` | `{ rc: true, cgi: true, extraInfo: true, session: false }` | Controls which diagnostic sections are included. `session` adds a `sessionId` row so alerts from one visitor can be tied together. |
| `codeSnippetLines` | `5` | Source lines shown either side of the failing line, with the failing line highlighted. `0` turns the snippet off. Costs one file read per alert and puts application source in the email. |
| `userProvider` | `""` | A closure that receives WireBox and returns a display string for the signed-in user. See the recipe below. The `user` row only appears when this is set. |
| `relativePaths` | `true` | Trims the application root from file paths so a path reads `/handlers/Main.cfc`. Paths outside the application root are always shown in full. Set `false` to keep every path absolute. |
| `includeQueryParams` | `true` | Include the bound parameter values from a failed query. The best data for reproducing a database error, but the values can contain whatever a visitor typed, and `maskKeys` cannot filter them because they carry no field names. |
| `maskQueryString` | `true` | Apply `maskKeys` and `maskKeyPatterns` to the query string shown in the Request section. Turning this off can put a secret from a GET request in email. |
| `emptyValueText` | `"N/A"` | Placeholder shown for a request value the request did not provide. |
| `includeHeaders` | `[ "Content-Type" ]` | Request headers shown in the Request section, matched ignoring case. `Cookie` and `Authorization` are never included, even when listed. |
| `includeRequestBody` | `false` | Include the raw request body. Useful for JSON and API endpoints, whose payload never reaches `rc`. JSON bodies get their fields masked at any depth, and a JSON body that cannot be walked is reported by size instead of printed. Form posts are skipped because `rc` already shows them masked. A body that is not JSON has no field names to match, so it is shown as sent. |
| `requestBodyMaxLength` | `4000` | Maximum characters of request body shown. |
| `maskKeys` | `[]` | Field names whose values are replaced with `*** masked ***` wherever they appear: `rc` keys, JSON body fields, and `extraInfo` keys, all at any nesting depth stopping at five levels, plus query-string field names. Matching is exact, ignoring case. Empty by default: masking is opt-in. |
| `maskKeyPatterns` | `[]` | Wildcard field-name patterns, checked only when the exact `maskKeys` lookup misses. `*` matches any run of characters; matching ignores case and covers the whole name. |
| `longValueMaxLength` | `500` | Per-value cap for string values found while walking `extraInfo` or a JSON body. Longer values keep this many characters plus a label stating the real size. `0` disables the per-value cap. |
| `longValueExemptKeys` | `[ "_stacktrace", "stacktrace" ]` | Keys whose values skip the per-value cap, matched exactly ignoring case, so stack traces keep their frames. The whole-output caps still apply. |
| `extraInfoMaxLength` | `2000` | Maximum characters of sanitized `extraInfo` shown, and the collection budget for its walk. |

Masking is opt-in and has its own section above: see [Masking and sanitization](#masking-and-sanitization) for the starter list, wildcard patterns, and long-value truncation.

### Upgrading past 2.4

Masking became opt-in: `maskKeys` no longer ships any default entries. An application that never set `maskKeys` and relied on `password`, `token`, and the other seven former defaults being hidden must now list its own field names — copy the starter list in [Masking and sanitization](#masking-and-sanitization) and keep what applies. Two behavior changes come with the same release: nested keys inside `rc` values and JSON request bodies are now masked (both used to check top-level names only), and string values longer than `longValueMaxLength` (500) are clipped with a size label; set it to `0` to keep whole values.

### Upgrading to 2.3

Two behavior changes to know about:

- Error signatures now include the first application-owned stack frame, so two different call sites that fail with the same message are throttled separately. Every signature changes once on upgrade, which restarts any open throttle window. No action is needed; a burst in progress during the deploy may send up to `maxPerWindow` extra emails.
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
- Masking is opt-in: `maskKeys` ships empty, and the exact match means every sensitive field name your application actually uses has to be listed. Review [Masking and sanitization](#masking-and-sanitization) before production use.

## Contributing

```bash
box run-script install:dependencies
box run-script start:2023
box testbox run
```

To run the harness on another engine, swap the start script: `box run-script start:boxlang` (BoxLang), `box run-script start:lucee5` (Lucee 5), `box run-script start:lucee6` (Lucee 6), or `box run-script start:2025` (Adobe 2025). All engines use the same port, so stop one before starting another.

The harness home page at <http://127.0.0.1:60310/> lists every failure scenario the module can be tested against, and can send the resulting alerts to a local SMTP server so you can read them as real email. See [docs/test-harness.md](docs/test-harness.md).

Releases must use `box run-script release`; do not run `box publish` directly from the repository root. See [RELEASE.md](RELEASE.md) for the routine and [docs/release-process.md](docs/release-process.md) for why.

## License

MIT
