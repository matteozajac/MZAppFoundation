# Report format and Pulse inspection

## Container

The iOS module is `MZAppFoundationReporting`. The app can configure an archive prefix; the default is `bug-report`. ZIP mode is on by default. The filename's lowercase UUID is the report ID, stable across share retries. Individual-file sharing remains available when QA turns ZIP off.

`report.json` (format `bug-reporter`, schemaVersion `2`) and `report.txt` are always included. Schema `1` title-based reports remain supported. The JSON includes:

- `id`, `capturedAt`: report identity and time reporting began.
- `title`, `description`, `steps`, `expectedResult`, `severity`: QA input. Schema 2 allows an empty title when a usable voice note is attached; QA can provide both.
- `metadata`: app name, `bundleIdentifier`, `version`, `build`, `device`, `os`, `locale`, plus host-supplied context. `device` is a hardware identifier (or simulator architecture), **not a device serial number**.
- `attachments`: actual selected attachment basenames.
- `attachmentStatus`: `logs`, `screenshot`, `video`, `audio` each `included`, `excluded`, or `unavailable` (`audio` is new in schema 2).
- `attachmentErrors`: capture/export errors for selected unavailable attachments.
- `logScope`: `currentSession` by default, or `allSessions`.
- Optional `screenshotCapturedAt` and `recordingDuration` (actual trimmed seconds).
- Optional `voiceNote`: `filename` (`voice-note.m4a`), `duration` (greater than zero, at most 300 seconds), `codec` (`aac`), `sampleRate` (`24000`), `channels` (`1`), optional `bitRate` (actual encoded bits per second; legacy reports specify the 48000 target), `transcriptionRequired` (`true`). This is the QA message recorded after the reporting form opens, separate from rolling screen video.

Selected available attachments are `screenshot.png`, `recording.mp4`, `voice-note.m4a`, and a native `.pulse` file (currently `logs.pulse`). No media is guaranteed. Failed/missing logs or voice notes must be called out. The inspector checks the manifest and actual file inventory, emits `voiceNote.available`, and marks `mediaVerified=false`. The transcription helper separately probes and decodes actual audio, recording verified properties in `transcription-status.json`. A `.m4a` without explicit voice metadata needs manual inspection; a silent `.mp4` never triggers transcription. Schema-less individual reports from older builds are accepted by the helper with a legacy warning. Unknown future schema versions require inspection before changing the parser.

AAC compresses while recording: five minutes at the preferred 48 kbps is about 1.8 MB plus container overhead. Encoders may select another AAC bitrate, so use the actual media and optional bitrate metadata for size estimates. Keep the original AAC; repeated lossy encoding would only reduce transcription quality. The Mac helper makes temporary mono 16 kHz PCM for Whisper and removes that intermediate afterward. ZIP compression is packaging, not a reason to re-encode audio. See [voice transcription](voice-transcription.md) when a report includes speech.

## Pulse 5.2.1

The `.pulse` file is a SQLite document, **not a ZIP or plain text**. Its `ZPULSEBLOBENTITY` table contains `ZKEY`/`ZDATA`:

- `database`: LZFSE-compressed Core Data SQLite store.
- `info`: archive information as JSON.
- 40-character hex keys: external body blobs; may themselves be LZFSE-compressed.

The helper keeps the native file intact, emits the decoded `logs.sqlite`, schema and per-table JSONL, and decodes body blobs. It reads SQLite in read-only immutable mode. See the pinned Pulse source under DerivedData `SourcePackages/checkouts/Pulse/Sources/Pulse/LoggerStore/` (`LoggerStore.swift`, `LoggerStore+Model.swift`, `LoggerStore+Entities.swift`) when the dependency/schema changes.

Useful tables/joins (all foreign keys refer to `Z_PK`):

| Table | Relevant fields |
| --- | --- |
| `ZLOGGERMESSAGEENTITY` | `ZTEXT`, `ZLABEL`, `ZLEVEL`, `ZCREATEDAT`, `ZSESSION`, `ZFILE`, `ZFUNCTION`, `ZLINE`, `ZTASK` |
| `ZNETWORKTASKENTITY` | `ZURL`, `ZHTTPMETHOD`, `ZSTATUSCODE`, `ZERRORCODE`, `ZERRORDOMAIN`, `ZERRORDEBUGDESCRIPTION`, `ZDURATION`, `ZSESSION`, `ZORIGINALREQUEST`, `ZCURRENTREQUEST`, `ZRESPONSE`, `ZREQUESTBODY`, `ZRESPONSEBODY` |
| `ZNETWORKREQUESTENTITY`, `ZNETWORKRESPONSEENTITY` | `ZHTTPHEADERS` and request/response details |
| `ZLOGGERSESSIONENTITY` | `ZID`, `ZCREATEDAT`, `ZVERSION`, `ZBUILD` |
| `ZLOGGERBLOBHANDLEENTITY` | `ZKEY`, `ZINLINEDATA`, `ZISUNCOMPRESSED`, `ZDECOMPRESSEDSIZE`, `ZRAWCONTENTTYPE` |

Pulse/Core Data date numbers are seconds since **2001-01-01 UTC**, not Unix epoch. JSONL adds `createdAtUTC`; source numeric values remain. Levels: 1 trace, 2 debug, 3 info, 4 notice, 5 warning, 6 error, 7 critical. JSONL adds `levelName`. UUIDs and short binary keys are represented as hex; large binary values retain a byte count and remain available in SQLite.

For each body handle, the helper uses inline bytes or the external hex-key file, checks `ZISUNCOMPRESSED`, then writes `blobs/<hex>.body`. JSONL `decodedBody` points there. Join a network task's body key to the handle's `Z_PK`; do not assume every request has a retained body. Consult content type before displaying binary data. Headers and bodies may contain credentials or personal data; keep them local and redact excerpts.
