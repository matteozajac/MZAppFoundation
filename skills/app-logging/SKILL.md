---
name: app-logging
description: Add, improve, or audit diagnostic logging in Apple apps using MZAppFoundation, structured errors, replaceable logging engines, and Pulse/PulseUI. Use for requests to add logs or fix missing error details; analytics tracking alone is a separate concern.
---

# App logging

Use JoinOurDay's error-first call shape: a short operation message plus the actual caught Error, with caller location and metadata kept separately. MZAppFoundation owns the reusable interfaces; Pulse is one engine and PulseUI is its inspector.

## Inspect before editing

Check the resolved foundation API, existing app logging facade, sinks, build compositions, diagnostics preferences, and failure owners. Structured errors require MZAppFoundation 0.2.0 or later; older versions only have message/metadata logging. Do not invent an unavailable API or flatten an error into a string as a substitute. Upgrade within authorized scope or report the missing capability.

## Implement

- Inject `AppLogging` or use the app's thin facade backed by `services.logger`. Feature code must not import Pulse or Sentry. The foundation composition routes error entries through diagnostics once; its local engine retains the raw Pulse sink to avoid recursion.
- Prefer `logger.error("Model loading failed", error: error, category: "model", metadata: ["model_id": .string(modelID)], file: file, function: function, line: line)`. At a direct call omit the source arguments; wrappers must accept caller defaults (`#fileID`, `#function`, `#line`) and forward them.
- When a real error exists, always pass it. Do not replace it with `localizedDescription`, an enum label, or a synthetic NSError. Message-only errors are for failures with no underlying Error.
- Capture `ErrorSnapshot(error)` synchronously before an actor hop or delivery queue. It retains type/domain/signed code and bounded underlying causes. Preserve causes through app-owned error wrappers; do not log at every rethrow.
- `ErrorStackProviding` preserves supplied stack provenance. Otherwise a snapshot captures a **reporting** stack. Swift Error does not automatically contain the original throw stack. Never claim reporting frames prove the throw location.
- Keep metadata out of messages: app/build/device context, model IDs, phases, timing, counts, and recovery are fields. Keep analytics event names stable. Do not apply analytics allowlists to diagnostic error evidence.
- Arbitrary error descriptions/userInfo may contain recordings, transcripts, URLs, or credentials. Foundation captures their identity without serializing these values. For app-owned errors with audited technical explanations, conform to `LoggableError`; `logMessage` must contain no user-authored content or secrets. Do not return arbitrary `localizedDescription` from this conformance. Preserve useful type/domain/code and stacks even when text is omitted.
- Log once at the boundary responsible for the failed operation. Expected cancellation is not an error. Recoverable fallback/degradation is a warning; frequent progress is debug. Avoid per-audio-buffer logging and duplicate analytics/diagnostic error reports. Delivery failures use a local fallback so they cannot recursively report themselves.
- Reuse PulseUI and existing developer-mode entrypoints; open the Logs view by default. Pulse 5.2.1 strips whitespace from metadata, so use the foundation adapter's tested preservation path and separate stack-frame fields rather than joining frames into one value. Keep persistence available independently of remote diagnostics consent. Do not enable providers, change release visibility, or add bug-report recording just because logging was requested.

## Verify

Test original error identity, negative codes, nested/cyclic cause bounds, caller forwarding, stack provenance, private-data exclusion, single-entry routing and remote opt-out. Build every supported platform. Trigger representative failures and inspect PulseUI details, including source and stack. Verify adapter payloads with a local/intercepted transport; do not confuse that with confirmed remote delivery or symbolication. Report actual evidence and remaining limitations.
