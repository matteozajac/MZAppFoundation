# Send phone bug reports to an agent

MZ Inbox is a local Mac menu bar app. Share an existing MZAppFoundation report ZIP from your iPhone to **Send to my agent**. The shortcut saves a copy to iCloud Drive; the Mac receives it, finds the app's configured repository, inspects its evidence, and starts Codex automatically. Existing reporting apps need no package update.

```text
iPhone report → Send to my agent → iCloud Drive/MZ Inbox/Incoming
                                        ↓
                              MZ Inbox on your Mac
                                        ↓
                          Repository → Codex → Findings
```

## Install on the Mac

Requirements: macOS 15 or later, iCloud Drive, Python 3.11 or later, and an installed Codex CLI with your existing sign-in. Building the companion also needs the Swift toolchain. The phone and Mac must use the same Apple account for iCloud Drive.

From this checkout:

```sh
python3 scripts/create_inbox_shortcut.py
python3 scripts/build_inbox.py --install --launch --login --discover-root ~/Developer
```

This builds `output/inbox/MZ Inbox.app`, installs it in `~/Applications`, and opens it at login. The builder records the chosen Python executable. Keep that Python installation available. The locally built app is signed for this Mac with ad hoc signing; it is not a notarized public distribution.

The installer creates **MZ Inbox/Incoming** and **MZ Inbox/Status** in iCloud Drive. Project discovery registers exact application bundle identifiers from unambiguous Xcode projects in the selected directory. Review those entries in **Settings → App projects**; add any missing app with **Add App Project**. Route an app to the Git repository root that owns its code. Names are display labels; routing uses the bundle identifier in `report.json`.

Routes default to **Investigate**. Change an individual app to **Prepare a fix** when you want reports from that app to trigger edits automatically, then save Settings.

## Add the phone shortcut once

1. The installer places the signed shortcut in iCloud Drive under **MZ Inbox/Send to my agent.shortcut**. In MZ Inbox on the Mac, **Phone Setup** shows these instructions and the shortcut file. You can also AirDrop `output/inbox/Send to my agent.shortcut` to the phone.
2. On the iPhone, open that file in Files and add it to Shortcuts.
3. In the setup question, choose **iCloud Drive → MZ Inbox → Incoming**, then finish adding the shortcut. Choose the folder on the iPhone so Shortcuts has that device's folder access.
4. In an app's bug reporter, create a report and tap **Share → Send to my agent**. Share one report ZIP at a time.

The folder selection is a setup step; subsequent reports save there automatically. The shortcut checks the `.zip` extension, copies the original bytes, and disables overwriting existing files. It shows **Queued for Mac** after saving. That confirms the phone has saved the report; it does not confirm the Mac has received it or the agent has started. The Mac validates the archive and its manifest before dispatching a task.

Shortcuts stores folder access as a device bookmark. A generated shortcut cannot safely include this Mac's bookmark as an iPhone destination. If you change the incoming folder, edit the shortcut's **Save File** action on the iPhone to choose the matching folder. Keep **Ask Where to Save** and **Overwrite If File Exists** off.

If the shortcut does not appear in the share sheet, open it in Shortcuts, enable **Show in Share Sheet**, and check that its input includes **Files**. Use it from the app's ZIP share sheet or share a report ZIP from Files. [Apple's share sheet instructions](https://support.apple.com/guide/shortcuts/launch-a-shortcut-from-another-app-apd163eb9f95/ios).

## What starts automatically

MZ Inbox waits for a stable, readable ZIP and preserves a private local original before inspecting it. It deduplicates by the manifest's report UUID and archive hash. Sharing the same report again does not start another agent. An unknown or disabled bundle identifier waits for an app route; saving the matching enabled route lets it proceed.

| App setting | Agent behavior | Where to review |
| --- | --- | --- |
| Investigate | Starts Codex with its read-only sandbox in the configured repository; asks it to explain the reported failure. | Report detail and saved result on the Mac. |
| Prepare a fix | Creates a separate Git worktree from the repository's current committed `HEAD`, starts Codex with its workspace-write sandbox, and asks for a scoped repair with relevant checks. Uncommitted changes in your original checkout are not copied. | Saved result and the report's worktree. |

Tasks read the checkout's instructions and the `app-bug-report` skill. Report notes, logs, filenames, media, and speech are treated as evidence. The task asks the agent to preserve that evidence and leave edits for review. It does not authorize commits, Git pushes, releases, deployments, or external messages.

Voice messages are transcribed on the Mac before the agent starts. They require `whisper-cli`, `ffmpeg`, `ffprobe`, and an existing multilingual Whisper GGML model selected in **Settings → Agent and voice notes**. A title-only report needs no speech tools. If transcription cannot finish, the report waits with an actionable status rather than discarding the recording or starting an agent without it.

The worker uses your selected Codex executable with its existing authentication and configuration; it does not select a separate agent profile. Report content read by that agent may be sent to its model service. Local transcription and queue storage do not establish local model inference. Review the configured account, connected tools, and data controls before enabling automatic processing.

The receiver runs one agent at a time. It preserves original reports, decoded evidence, transcripts, task prompts, event logs, and results under `~/Library/Application Support/MZ Inbox/state`. Incoming ZIPs remain in iCloud Drive after processing.

## Status and recovery

Open the menu bar app to see reports, read a result, reveal the original evidence, or open a fix worktree. **Pause** prevents new work from starting; an active task finishes under its time limit. Failed, interrupted, or usage-limited tasks require an explicit **Retry**. Previous attempts and worktrees are preserved.

On the phone, Files → **iCloud Drive → MZ Inbox → Status** contains one small JSON receipt per report. It includes the report UUID, status, timestamps, and a short explanation. Agent results, app/project paths, report text, and attachment contents are kept out of these receipts. The first version has no iPhone status app or push notification.

| Status | Meaning |
| --- | --- |
| Queued / Inspecting / Transcribing | The Mac has preserved the report and is preparing its evidence. |
| Waiting for route | Add or enable the app's exact bundle identifier and repository in Settings. |
| Waiting for transcription | Correct the local speech tools/model, then retry if the previous transcription failed. |
| Investigating | Codex is working on the Mac. |
| Completed / Fix ready | A completed agent result is saved on the Mac. A fix remains for human review. |
| Failed / Rate limited / Interrupted | Read the report detail, resolve its stated cause, and retry explicitly. |
| Rejected | The archive or report identity could not be accepted; preserve it and send a fresh report. |

If the Mac is asleep, logged out, or offline, delivery waits until iCloud syncs and MZ Inbox runs again. If the phone is offline, its saved file waits for iCloud synchronization. **Queued for Mac** is not a synchronization acknowledgment. [Apple's iCloud Drive setup guide](https://support.apple.com/guide/icloud/set-up-icloud-drive-mm203b05aec8/icloud).

If iCloud Drive stops responding, MZ Inbox shows the delay, limits cloud operations, and continues processing reports already saved privately on the Mac. Cloud receipt updates retry when access returns. Opening a cloud folder also has a time limit so the app's controls stay available.

If Finder can open the shared folders but MZ Inbox keeps timing out, open **Settings** and use **Choose…** to select both delivery folders again: **Incoming reports → MZ Inbox/Incoming** and **Phone status → MZ Inbox/Status**, then **Save Settings**. Selecting the folders through macOS's picker lets the system grant access to the app; a correct path filled in by the installer may not be enough. Allow an active investigation to finish before quitting or reinstalling the app. Phone status synchronization retries after the investigation finishes.

An interrupted agent run can have partial findings or edits. Review its saved attempt before retrying; the receiver does not silently replay a task with an uncertain outcome.

## Configuration and development

Settings are saved in `~/Library/Application Support/MZ Inbox/config.json`. Reinstalling preserves an existing configuration. A route has this shape:

```json
{
  "bundleIdentifier": "com.example.MyApp",
  "name": "My App",
  "repository": "/absolute/path/to/MyApp",
  "mode": "diagnose",
  "enabled": true
}
```

Use the actual app bundle identifier and actual repository root. Supported modes are `diagnose` and `fix`; there is no guessed default repository for an unknown app.

The standalone receiver can also be operated without the menu bar UI:

```sh
python3 Tools/MZInbox/inbox.py --config "$HOME/Library/Application Support/MZ Inbox/config.json" watch
python3 Tools/MZInbox/inbox.py --config "$HOME/Library/Application Support/MZ Inbox/config.json" status
python3 Tools/MZInbox/inbox.py --config "$HOME/Library/Application Support/MZ Inbox/config.json" retry REPORT_UUID
```

Do not run another receiver alongside the app; the queue has a single-worker lock. The `scan` command performs one scan and may start an agent, so use it only with the intended configuration. Synthetic validation belongs in an isolated incoming/state folder.

`create_inbox_shortcut.py --unsigned-only` produces an inspectable plist without signing. Normal generation invokes Apple's `shortcuts sign --mode anyone`; Apple's service receives the shortcut definition for validation, with no report data or credentials included. [Apple's shortcut signing documentation](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac).

The shortcut's native syntax and import setup question were verified on the development Mac. A synthetic Mac command-line run stalled before copying its file and was canceled; native iPhone transfer still needs a device check. See [validation evidence and remaining device checks](report-inbox-validation.md). Signing and importing a shortcut do not establish that a physical iPhone has shared a report through iCloud to this Mac.
