# errorAlerts reference

Start with the [README](../README.md) to install the module and receive an alert.
Use this guide when you need more settings or a different reporting setup.

- [Settings](#settings)
- [Configuration recipes](#configuration-recipes)
- [Masking and request data](#masking-and-request-data)
- [Repeated errors and digests](#repeated-errors-and-digests)
- [Pages outside ColdBox](#pages-outside-coldbox)
- [Custom notifiers](#custom-notifiers)
- [Troubleshooting](#troubleshooting)
- [Upgrading](#upgrading)

## Settings

Set overrides in the struct returned by `configure()` in
`config/modules/errorAlerts.cfc`. Settings you leave out keep their defaults.
Restart or reinitialize ColdBox after changing the configuration.

### Email and log levels

| Setting | Default | What it controls |
|---|---|---|
| `enabled` | `true` | Whether alerts are active, including in development. |
| `to` | `""` | Recipient address. Required by the built-in email notifier. |
| `from` | `""` | Sender address. Uses `to` when blank. |
| `subjectPrefix` | `""` | Text before the subject. Uses the ColdBox app name when blank. |
| `notifier` | `"EmailNotifier@errorAlerts"` | WireBox mapping ID of the notification provider. |
| `deliveryMode` | `"queue"` | `"queue"` sends in the background; `"send"` waits for delivery. |
| `levelMin` | `"FATAL"` | Start of the allowed LogBox level range. |
| `levelMax` | `"ERROR"` | End of the allowed LogBox level range. Use `"WARN"` to include warnings. |

LogBox orders levels as `OFF`, `FATAL`, `ERROR`, `WARN`, `INFO`, and
`DEBUG`. These level settings control logged messages. Unhandled exceptions are
also captured by the ColdBox interceptor.

### Repeated errors and ignored errors

| Setting | Default | What it controls |
|---|---|---|
| `throttle.maxPerWindow` | `3` | Separate alerts allowed for a matching error during one window. |
| `throttle.windowSeconds` | `600` | Window length in seconds, starting with the first occurrence. |
| `throttle.maxTrackedSignatures` | `500` | Maximum error groups tracked at once. Additional groups send without throttling. |
| `digestFlushSeconds` | `60` | How often to check for summaries ready to send. |
| `digestSampleSize` | `5` | Maximum distinct routes and client IP addresses listed in a digest. `0` omits both lists. |
| `normalizeSignatures` | `true` | Treats numbers and UUIDs in messages as placeholders when grouping errors. |
| `ignoreCategories` | `[ "cbmailservices", "coldbox.system.Bootstrap" ]` | Log category prefixes that never produce alerts. |
| `ignoreExceptionTypes` | `[]` | Exact exception type names to ignore, without case sensitivity. |
| `suppressDuplicateFrameworkLogs` | `true` | Skips the logged copy of an error that ColdBox's RestHandler also reports through `onException`. |

Keep `suppressDuplicateFrameworkLogs` enabled unless you unregister
`UnhandledExceptionCapture@errorAlerts`. The interceptor's report contains the
stack frames and source information needed for the alert.

### Request details

| Setting | Default | What it controls |
|---|---|---|
| `includeScopes` | `{ rc: true, cgi: true, extraInfo: true, session: false }` | Includes the request collection, CGI details, extra log data, or session ID. |
| `userProvider` | `""` | Function that receives WireBox and returns text identifying the signed-in user. |
| `includeQueryParams` | `true` | Includes bound SQL values for database errors. These values are not key-masked. |
| `includeHeaders` | `[ "Content-Type" ]` | Request headers to show, without case sensitivity. |
| `includeRequestBody` | `false` | Includes non-form request bodies. See the masking limits below. |
| `maskQueryString` | `true` | Applies masking rules to query string values. |
| `relativePaths` | `true` | Removes the app root from file paths. Paths outside the root stay absolute. |
| `emptyValueText` | `"N/A"` | Text used for missing or blank request values. |

`session` adds a session ID, not the full session scope. A live session ID may let
someone impersonate a visitor, so enable it only when you need that information.
`Cookie`, `Authorization`, and `Proxy-Authorization` headers are always excluded
from the Request section, even if listed in `includeHeaders`.

### Masking and output limits

| Setting | Default | What it controls |
|---|---|---|
| `maskKeys` | `[]` | Full field names whose values are hidden. Matching ignores case. |
| `maskKeyPatterns` | `[]` | Wildcard field names. `*` matches any number of characters. |
| `longValueMaxLength` | `500` | Character limit for strings in `extraInfo` and JSON bodies. `0` disables this per-value limit. |
| `longValueExemptKeys` | `[ "_stacktrace", "stacktrace" ]` | Full key names that skip the per-value limit, without case sensitivity. |
| `requestBodyMaxLength` | `4000` | Character limit for the request body section. |
| `extraInfoMaxLength` | `2000` | Character limit for extra log data. |
| `exceptionFieldMaxLength` | `2048` | Character limit for each exception `detail` and `extendedInfo` field. `0` disables this limit. |
| `maxBodyBytes` | `102400` | Rendered email size limit. Lower-priority sections are removed first. |
| `rcValueMaxLength` | `200` | Character limit for each displayed request-collection value. |
| `stackFrames` | `10` | Number of stack frames to show. The first application frame is added if it falls beyond the limit. |
| `applicationFramePrefixes` | See below | Folder prefixes used to identify stack frames from your application. |
| `codeSnippetLines` | `5` | Source lines shown before and after the failing line. `0` omits snippets. |

The default `applicationFramePrefixes` are `/handlers/`, `/models/`, `/views/`,
`/layouts/`, `/config/`, `/interceptors/`, and `/modules_app/`. Installed
dependencies under `/modules/` are not included. Source snippets put application
code in the email, so use `codeSnippetLines : 0` if you do not want to share it.

Partial overrides of `throttle` and `includeScopes` keep missing defaults:

```cfc
throttle      : { windowSeconds : 300 },
includeScopes : { extraInfo : false }
```

Arrays replace their defaults. Include any default entries you still need when
changing `ignoreCategories`, `applicationFramePrefixes`, or other array settings.
The defaults are defined in [ModuleConfig.cfc](../ModuleConfig.cfc).

## Configuration recipes

These snippets are entries for the struct returned by `configure()`, unless a
complete file is shown. The README covers [environment overrides](../README.md#disable-alerts-in-development)
and [changing the alert limit](../README.md#change-the-alert-limit).

### Include warnings

```cfc
levelMin : "FATAL",
levelMax : "WARN"
```

### Ignore expected errors

```cfc
ignoreExceptionTypes : [ "MyApp.ExpectedException" ],
ignoreCategories : [
    "cbmailservices",
    "coldbox.system.Bootstrap",
    "myapp.healthcheck"
]
```

Category matching ignores case and checks the start of the name. Keep
`cbmailservices` to avoid alerts about failed alert emails. Keep
`coldbox.system.Bootstrap` to avoid duplicate reports of unhandled exceptions.

### Identify the signed-in user

Set `userProvider` to a function that receives WireBox and returns a user label.
This example assumes your app has a `UserService` with a `getCurrentUserEmail()`
method that returns `""` when nobody is signed in:

```cfc
userProvider : function( wirebox ){
    return wirebox.getInstance( "UserService" ).getCurrentUserEmail();
}
```

Use your app's service and method names. If the function fails, the alert still
sends and the user row shows `emptyValueText`.

### Include API request bodies

```cfc
includeRequestBody : true
```

JSON API input is not normally in the request collection (`rc`). This setting adds
it to a separate section. Form posts remain excluded because `rc` already has
their fields. Read the [masking limits](#what-masking-does-not-hide) before enabling it.

### Save local emails as files

Set `deliveryMode : "send"` in your errorAlerts configuration and keep `to` set.
Then create `config/modules/cbmailservices.cfc`:

```cfc
component {
    function configure(){
        return {
            defaultProtocol : "default",
            mailers : {
                "default" : {
                    class      : "File",
                    properties : { filePath : "/mail-spool" }
                }
            }
        };
    }
}
```

Trigger an error and open the generated HTML file in the app's `mail-spool`
folder. This is for local testing. Restore your sending mailer for production.

## Masking and request data

`maskKeys` and `maskKeyPatterns` hide matching values in the request collection,
JSON bodies, plain structs and arrays passed as `extraInfo`, and query strings.
Masked values show `*** masked ***`. A matching container key hides all its
contents. Neither list has any entries by default.

### Choose field names and patterns

Exact matching ignores case but needs the full key. Add `newPassword` separately
if you already list `password`. A longer starter list is:

```cfc
maskKeys : [
    "password", "passwd", "token", "secret", "apikey", "api_key",
    "authorization", "creditcard", "cvv", "ssn", "cardNumber",
    "client_secret", "access_token", "refresh_token"
]
```

Keep the names your application uses and add any missing ones. To match several
versions of a field name, use a pattern:

```cfc
maskKeyPatterns : [ "*socialsecurity*" ]
```

`*` is the only wildcard. Patterns ignore case and match the complete key. They
are checked when no exact `maskKeys` entry matches. Keep patterns narrow:
`*token*` also hides useful fields such as `tokenCount` and `nextPageToken`.

### What masking does not hide

Key masking needs a field name. It cannot remove secrets from:

- Error messages, exception `detail`, or exception `extendedInfo`.
- Bound SQL values. Set `includeQueryParams : false` to omit those values.
- Plain strings, XML, or other non-JSON request bodies.
- Fields inside component instances, Java objects, or query rows.
- Client IP addresses listed in digests. Set `digestSampleSize : 0` to omit the lists.

Pass plain structs or arrays with only the fields you need instead of whole
objects. An object marker in the `rc` table does not mean its fields were masked
when the object was logged elsewhere.

Headers blocked in the Request section may still appear inside logged
`extraInfo`. Add the relevant field names to `maskKeys` for that data too.

### Request bodies and size limits

When request bodies are enabled, JSON objects and arrays have their fields
checked for masking. JSON over 2,097,152 characters, JSON that fails to parse, and
single JSON values such as strings or numbers are reported by size instead.
Binary bodies also show only their size.

Non-JSON bodies appear as sent, up to `requestBodyMaxLength`. Engines can treat
malformed JSON differently, so a body you intended as JSON may appear as plain
text. Leave `includeRequestBody` off if that text could contain secrets.

Nested structs and arrays stop after five levels or when the section limit is
reached. Omitted content gets a placeholder. Long strings keep their beginning
and show their original size. Keys in `longValueExemptKeys` skip the per-string
limit, but section and email limits still apply. Shortening content does not
remove secrets from it.

## Repeated errors and digests

Throttling limits separate alerts for matching errors. The default window starts
with the first occurrence and lasts ten minutes. If an error occurs five times
within that window:

1. The first three occurrences produce separate alerts.
2. The next two are counted without separate alerts.
3. After the window ends, a digest reports those two additional occurrences.

The module checks for ready digests every 60 seconds by default. A new occurrence
after a window ends can also trigger the pending digest. Queued email delivery
can add more delay.

Errors are grouped by log category, the first 200 message characters, the first
stack frame, and the first frame from application code. By default, numbers and
UUIDs are replaced when comparing messages. `Order 123 failed` and
`Order 456 failed` can therefore share a group when the category and frames match.

Counts and pending digests live in memory. Each server has separate counts.
Restarting or reinitializing the app clears them and discards unsent digests.
When 500 groups are tracked, new groups send without throttling until space is
available. Change `throttle.maxTrackedSignatures` to adjust that limit.

A client can supply `X-Forwarded-For`, which is used for IP samples. These
addresses may not identify the caller reliably.

## Pages outside ColdBox

Older `.cfm` pages may run without ColdBox. Report their errors through
`Application.cfc`'s `onError()` method. The pages must share the ColdBox
application's `this.name`, and `application.cbController` must be available.
A separate application with a different name is not supported by this setup.

Add this method to the `Application.cfc` that handles those pages. If you already
have `onError()`, add the reporting block to it and keep your existing error page.

```cfc
function onError( required any exception, string eventName = "" ){
    try {
        var reinitInProgress = structKeyExists( application, "fwReinit" ) && application.fwReinit;
        if ( !reinitInProgress && structKeyExists( application, "cbController" ) ) {
            application.cbController
                .getWireBox()
                .getInstance( "CaptureService@errorAlerts" )
                .captureException( arguments.exception );
        }
    } catch ( any e ) {
        // A failed alert must not stop the error page from being shown.
    }

    cfheader( statusCode = 500 );
    writeOutput( "<h1>Something went wrong</h1>" );
}
```

If a subfolder has its own `Application.cfc`, that file must define `onError()`
or get it by extending or including the root file. `captureException()` never
throws an exception back to its caller. It uses the same ignore rules, masking,
throttling, and notifier as ColdBox reports, and checks for duplicate reports
within the request. It ignores aborts and redirects and reports the original
error from Adobe's `EventHandlerException` wrapper.

Add the older folder to `applicationFramePrefixes` so errors from different
lines in your application can be grouped separately. Include the defaults:

```cfc
applicationFramePrefixes : [
    "/handlers/", "/models/", "/views/", "/layouts/",
    "/config/", "/interceptors/", "/modules_app/", "/admin/"
]
```

The alert shows "not a ColdBox request" instead of routing rows. Its `rc` section
combines FORM and URL fields, with URL values replacing FORM values for the same
key. Masking rules still apply. `enabled` and environment overrides still apply
too. A `userProvider` that needs a ColdBox request may fail; its row then shows
`emptyValueText`.

Keep queued delivery for these pages, especially after a request timeout.
On Lucee and BoxLang, the method reloads module mappings before reporting the
error, including when `onRequestStart()` failed before ColdBox ran. You do not
need to reload those mappings yourself.

## Custom notifiers

To send alerts somewhere other than email, create a singleton that implements
`INotifier`. Its `sendNotification()` method receives an error or digest struct:

```cfc
component singleton implements="errorAlerts.models.notifiers.INotifier" {
    void function sendNotification( required struct payload ){
        try {
            // Send payload to your alert service.
            // payload.type is "error" or "digest".
        } catch ( any exception ) {
            // Handle delivery failures without throwing or logging at ERROR.
        }
    }
}
```

Register the component in WireBox, then set its mapping ID:

```cfc
notifier : "MyNotifier"
```

Custom notifiers do not require `to`. Handle their delivery failures without
throwing into the request. Logging those failures at `ERROR` or `FATAL` can
create another alert. See [PayloadBuilder.cfc](../models/PayloadBuilder.cfc) for
the fields in error and digest payloads.

## Troubleshooting

### No email arrives

Start with the [README checklist](../README.md#no-email-arrived). Also check:

- The error's category or exception type is not on an ignore list.
- Your cbmailservices default mailer sends email rather than storing or discarding it.
- Temporarily using `deliveryMode : "send"` removes any background queue delay.
- Both the errorAlerts digest task and cbmailservices mail queue task can run.

Delivery failures do not replace the application's error page. Check server
console output, error logs, and cbmailservices logs for the cause.

### Errors outside ColdBox are not reported

Check the [onError example](#pages-outside-coldbox). Confirm that the pages share
the ColdBox application and that their `Application.cfc` handles the error.
Aborts and redirects do not produce alerts. Look for console messages starting
with `errorAlerts captureException failed` if reporting fails.

### Later alerts or digests are missing

Repeated errors wait for a digest after the alert limit is reached. Allow time
for the window to end, the next digest check, and queued mail delivery.
Restarting or reinitializing the app before that check discards pending digests.

### More alerts arrive than expected

Each server has its own alert counts. Restarting or reinitializing resets them.
Different categories, messages, or application stack frames may also put errors
in separate groups. Groups beyond `throttle.maxTrackedSignatures` send without
throttling.

## Upgrading

- **From before 2.5:** set `maskKeys` explicitly if you relied on its old defaults.
  Masking is now off until configured. Review nested request data and long-value limits.
- **From before 2.3:** errors from different application lines may use separate
  groups. Existing groups restart during the upgrade. File paths inside the app
  root are now relative; set `relativePaths : false` to keep absolute paths.
- **From 2.0:** masking uses exact names starting in 2.1. List `apiToken`
  explicitly if you previously relied on `token` matching part of that name.

See the [changelog](../CHANGELOG.md) for the full release history.

## Project development

For local scenarios and test instructions, see the [test harness guide](test-harness.md).
For release steps, see [RELEASE.md](../RELEASE.md) and the
[release process notes](release-process.md).
