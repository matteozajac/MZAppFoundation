# Bug reporting validation — 2026-09-29

MZAppFoundation 0.3.0 adds iOS reporting behind an explicit reporting-enabled developer-tools overload. Existing console-only consumers and SDK-free core interfaces remain compatible. The package keeps iOS/visionOS 26 deployment requirements and Pulse 5.2.1.

## Verified

- 30 reporting tests pass: real AAC/video encoding and ZIP export, title-or-audio validation, 300-second audio acceptance and over-limit rejection, cancellation during permission requests, bounded recent-video retention, ReplayKit lifecycle ordering, and native Pulse export.
- 22 core tests and two logging adapter tests pass.
- Three iOS UI tests pass across the sample suite and targeted reporting rerun: existing app/logging behavior, Ladybug entrypoint, required-description validation, title sharing, cancellation and draft preservation. The reporting test handles both popover and sheet forms of the native share controller.
- 39 Python/Ruby tests pass: setup idempotence, native package-pin upgrades, microphone-purpose preservation and verification, archive validation, legacy/title/audio recognition, and transcription failure handling. CI now discovers all Python tooling tests.
- The generic inspector decoded an actual Foundation test ZIP containing Pulse 5.2.1 messages/network bodies, PNG and MP4 without warnings. A separate audio-only ZIP retained its original AAC bytes and was recognized as requiring transcription. These contain synthetic fixtures, not microphone recordings.
- The generic Mac helper inspected and transcribed synthetic English and Polish speech locally with whisper.cpp and its multilingual `small` model. Both runs wrote completed status, source provenance, TXT, JSON and SRT output.
- iOS and visionOS local samples compile. Binary audits find Pulse and no RevenueCat, Sentry, Firebase Analytics or GoogleAppMeasurement matches in either local app.
- iOS and visionOS Internal device compositions compile with signing disabled. Both built iOS apps contain the microphone purpose string and version 0.3.0.
- Both changed skills pass the skill-creator validator. Debug probes are removed from shipping source.

## Live microphone limitation

The live microphone UI test was attempted and failed on this iOS 27 simulator: permission was granted and the audio session activated, but `AVAudioRecorder.record` returned false. A minimal PCM recorder also failed, both with record/measurement and play-and-record/default audio sessions. Live recording was not validated on this host. The strict microphone test remains available with test-runner environment `MZ_TEST_LIVE_MICROPHONE=1`; default runs explicitly skip it rather than claiming a recording success.

During those probes, explicit AAC bitrate settings also failed preparation. The recorder now retries using the system-selected AAC bitrate while preserving mono 24 kHz output. The manifest records the actual encoded bitrate when available, and the Mac inspector accepts automatic-rate files. This fallback passed preparation on the simulator, but does not resolve the separate live microphone limitation.

No physical-device microphone/Bluetooth or call-interruption behavior, five-minute wall-clock automatic stop, ReplayKit consent/performance, completed external sharing, or production delivery is claimed. Media remains local until the user chooses a share destination. visionOS/macOS screen/voice reporting and consumer-app migrations are outside this release.

## Local evidence

Artifacts remain ignored under `output/`; XcodeBuildMCP retains build logs and xcresults. Key result bundles from this run:

- Reporting: `test_sim_2026-09-29T20-47-53-152Z_pid31936_06d761d3.xcresult`.
- Reporting UI: `test_sim_2026-09-29T20-48-33-713Z_pid33770_0eb479fa.xcresult` (one pass, one explicit microphone skip).
- Logging adapters: `test_sim_2026-09-29T20-49-21-442Z_pid35330_b1ace42a.xcresult`.
- `output/native-pulse-inspection/`, `output/native-audio-inspection/`, `output/mac-transcription-en/`, `output/mac-transcription-pl/` and `output/python-validation.log`.
