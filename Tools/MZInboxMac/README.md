# MZ Inbox for Mac — unreleased

A native menu bar receiver for MZAppFoundation report ZIPs. It watches a shared inbox, requests downloads for iCloud placeholders, launches the bundled Python worker, and displays a private local queue. Closing its window keeps the receiver running. This companion is separate from the Swift package and has no published installer or notarized distribution in this repository.

## Requirements and build

- macOS 15+ and Swift 6.2+.
- Python 3.11+ for the bundled worker and packaging script.
- An installed, authenticated Codex CLI for agent processing. The installer checks that `codex` is on PATH; authentication must be verified separately.
- For phone delivery, iCloud Drive enabled on the Mac and iPhone using the same Apple account, plus Shortcuts on the iPhone.
- For voice reports, FFmpeg/ffprobe, whisper.cpp's `whisper-cli`, and a local multilingual Whisper model. Select installed tool/model paths as appropriate for your machine.

From the repository root:

```sh
swift build --package-path Tools/MZInboxMac -c release
python3 scripts/build_inbox.py
```

The packaging script creates `output/inbox/MZ Inbox.app`, bundles the worker/report tools and artwork, and signs the bundle ad hoc for local use. `--python` selects a Python 3.11+ executable. The standalone Swift executable lacks bundled resources and shows a setup message; use the packaged app for processing.

To build the optional phone shortcut, run `python3 scripts/create_inbox_shortcut.py`. It invokes macOS Shortcuts signing through Apple's service. `--unsigned-only` writes inspectable workflow source without signing; unsigned source is not the importable shortcut.

To package, install, and launch locally:

```sh
python3 scripts/build_inbox.py --install --launch
```

`--login` additionally creates a launch-at-login entry. `--discover-root ../Apps` optionally discovers unambiguous app bundle identifiers under a directory you choose; review the resulting routes. These options require `--install`. Installation writes to `~/Applications/MZ Inbox.app` and initializes per-user configuration without replacing existing settings. No login item or project discovery is required for a manual configuration.

The packaged app includes:

```text
Contents/MacOS/MZInbox
Contents/Resources/AppIcon.icns
Contents/Resources/RabbitTemplate.png
Contents/Resources/worker/inbox.py
Contents/Resources/report-tools/…
Contents/Resources/Send to my agent.shortcut  (optional)
```

The script writes the app's bundle identifier, `LSUIElement`, icon name, and `MZInboxPythonPath` into `Info.plist`. The app also searches standard Homebrew/system executable locations for Python, and the worker PATH includes standard Homebrew locations. Keep the configured Python and Codex executables installed after packaging.

## Configure delivery and project routes

The app reads `~/Library/Application Support/MZ Inbox/config.json`. Settings offers folder pickers and project configuration without hand-editing JSON. Defaults are iCloud Drive → MZ Inbox → Incoming and Status; private queue state, evidence, and results stay under Application Support.

The initial Codex executable path is `/opt/homebrew/bin/codex`. Set the actual executable in Settings for Intel Homebrew, npm, or another installation. The worker uses that executable's existing authentication and configuration; it does not create a separate agent profile.

Add each target app's bundle identifier, display name, and local Git repository. **Investigate** is the default. **Prepare a fix** permits the worker to prepare changes in a separate worktree; review that mode before enabling automatic processing. An unknown app waits until you choose **Connect to Project** in its report details. Save Settings after editing routes.

**Phone Setup** locates the bundled shortcut and instructions. On the iPhone, open `Send to my agent.shortcut` in Files → iCloud Drive → MZ Inbox, or receive it with AirDrop, then import it into Shortcuts. Choose the Incoming folder on the iPhone during setup so folder access belongs to that device. Its Share Sheet action saves report ZIPs there.

Both report contents and repository contents should come from sources you trust. Inspect reports and route/mode choices before enabling an agent against a repository. Signing a shortcut or building the receiver does not prove physical phone-to-Mac transfer; verify the complete path with your devices and iCloud account.

Report content read by the configured agent may be sent to its model service. Local queue storage and local voice transcription do not imply local model inference. Review the agent account, connected tools, and data controls before enabling automatic processing.

## Processing and recovery

- The worker starts when the menu bar app launches and reloads configuration between scans.
- A separate serial cloud task requests iCloud downloads so slow File Provider metadata does not block local queue updates or Settings saves.
- **Pause Processing** leaves incoming files queued and lets an active agent finish.
- Worker stdout/stderr are written to `~/Library/Application Support/MZ Inbox/receiver.log`.
- Queue snapshots are read from `statePath/queue.json`; report details open source evidence and results.
- Folder/result launches use a bounded background helper; a stalled iCloud/Finder request is surfaced as an error.
- Failed, interrupted, transcription-blocked, and rate-limited reports offer **Retry Report**.
- **Quit MZ Inbox** sends SIGTERM to the worker. It stops accepting work and finishes an active agent, so the worker may remain alive briefly after the UI exits. Its lock prevents a second launch from duplicating active work.

Opening the installed app starts the receiver again. The Mac must be awake for agent processing. Shared Status files contain delivery state rather than private project paths or report evidence. A completed investigation is not a confirmed fix, and provider/device behavior requires its own validation.

See the [report inbox guide](../../docs/report-inbox.md) and [verification guide](../../docs/verification.md) for worker details and supported checks.
