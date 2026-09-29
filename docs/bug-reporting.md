# Local bug reporting in 0.3.0

On iOS, Foundation can retain the last 60 seconds of silent app activity and add a Ladybug report action to Pulse. The report form supports a title, a voice message up to five minutes, or both. It includes optional screenshot/video/Pulse logs, app and device metadata, and a native share sheet. ZIP sharing defaults on; cancelling the share sheet keeps the draft, while completing or discarding clears its temporary files.

## Integrate

Use one `DeveloperReporting` instance per app process, alongside the existing services composition. Register the modifier on the principal app scene; it uses that scene's window for screenshot and presentation. Preserve unrelated URL handlers and scene wiring.

```swift
import MZAppFoundationLocal

@MainActor enum AppInfrastructure {
    static let reporting = DeveloperReporting(archivePrefix: "myapp")
}

// In the iOS WindowGroup's root view:
ContentView()
    .appDeveloperTools(services.developerOptions, reporting: AppInfrastructure.reporting)

// Inside the app's developer Settings form:
DeveloperReportingSettings(reporting: AppInfrastructure.reporting)
```

The host app must contain a nonempty `NSMicrophoneUsageDescription`, covering bug narration and any other existing microphone use. For setup-managed apps, `bug_reporting: true` generates `MZBootstrap.reporting`, preserves existing purpose text or adds `microphone_usage_description`, and verifies purpose text plus reporting-enabled entrypoint wiring. `report_archive_prefix` defaults to `bug-report`. Reporting is opt-in in setup configuration; configs without it retain the previous bootstrap and console-only interface. The example config enables it for new iOS integrations.

The existing `appDeveloperTools(options)` overload keeps console-only behavior. `DeveloperReporting.recordsRecentActivity` and the settings view expose the persisted screen-recording preference; its initial default is on, subject to developer mode, foreground activity and ReplayKit consent. Microphone recording starts only after the user taps Record and grants permission. Backgrounding/interruption stops voice capture and preserves valid partial audio. It never resumes voice capture automatically.

## Modules and platforms

- `MZAppFoundationReporting`: iOS media capture, reporting form, schema and archive implementation; no third-party dependencies. Available as a separate product for custom host integrations. The root package's iOS 26 deployment requirement still applies.
- `MZAppFoundationLocal`: Pulse 5.2.1 attachment adapter, `DeveloperReporting`, settings and developer-tools integration. Existing error metadata handling remains in the Pulse adapter.
- `Packages/Core`: unchanged SDK-free domain interfaces; no media or UI dependencies.
- visionOS/macOS: retain their existing console interfaces. Version 0.3.0 does not claim screen/voice reporting parity on those platforms. iOS reporting sources are conditionally compiled and the local composition depends on them only on iOS.

No app migration is implicit in publishing the package. In particular, JoinOurDay's iOS 18.2/Pulse 5.2.3 local integration remains separate. Do not raise deployment targets or change SDK pins as an incidental setup step.

## Capture and privacy

Recent screen activity uses bounded five-second H.264 segments, up to 60 seconds, 720 × 1280, 15 fps and roughly 2 Mbps. The buffer budget is 32 MiB. Reporting freezes capture before the console, waits for ReplayKit to release, and captures the underlying app after the console closes. Screen video is silent; protected/system-owned surfaces may be absent. Turning off developer mode or backgrounding clears unreported history.

Voice recording uses AAC/M4A, mono 24 kHz, a preferred 48 kbps (approximately 1.8 MB for five minutes). Encoders that reject that rate use their automatic AAC bitrate; the manifest records the actual encoded bitrate when available. Export copies the original compressed bytes. There is no phone transcription, speech-recognition entitlement, cloud upload or new remote SDK. QA text and media stay in explicit local report attachments, separate from logging, analytics and Sentry. Hosts remain responsible for the content already recorded by their log provider.

## Mac inspection

Run `python3 scripts/install_skill.py` to install the canonical `app-bug-report` skill alongside setup and logging skills. It recognizes the `bug-reporter` manifest (schema 1/2), resolves the originating app from metadata, reads native Pulse exports, and requires local transcription when audio is present. `whisper-cli` plus FFmpeg uses a multilingual model stored outside the repository. TXT/JSON/SRT transcripts and source provenance remain in ignored output. See [the skill](../skills/app-bug-report/SKILL.md).

## Verification

`Samples/project.yml` includes `FoundationReportingTests`, covering video retention/encoding, ReplayKit lifecycle, title-or-audio validation, five-minute file limits, permission cancellation, Pulse session export and real ZIP round trips. `FoundationLocal` UI tests exercise the Ladybug form, title validation, cancelled sharing and draft preservation. The separate live microphone UI test covers recording, playback, deletion and title fallback; opt in with the test-runner environment `MZ_TEST_LIVE_MICROPHONE=1` on a host with working microphone input. It is skipped by default and must not be counted as microphone validation. UI-test sample launches disable rolling screen capture so a ReplayKit consent prompt cannot obscure unrelated tests; enable it through the developer settings when checking recording consent.

Run the Python setup/inspection/transcription suite with `.venv/bin/python -m unittest discover -s scripts -p 'test_*.py'` (use repository Ruby gems for native project tests), plus core, adapter, iOS and visionOS sample checks. Export the reporting test's ZIP attachment from its xcresult and run the generic inspector against it to verify the pinned Pulse format.

Simulator evidence does not establish physical microphone/Bluetooth behavior, call interruptions, ReplayKit performance, or actual five-minute automatic stop timing. Check those on a device before claiming device validation.

See [0.3.0 validation evidence and limitations](bug-reporting-validation.md).
