# MZ Inbox validation

Validated on 2026-10-04 with Xcode 27, Swift 6.4 in Swift 6 language mode, Python 3.13, and Codex CLI 0.160.0.

## Automated checks

- 34 receiver tests pass. Coverage includes stable ingestion, bundle-ID routing, route edits without resending, duplicate/colliding UUIDs, unsafe ZIPs and symlinks, interruption, durable retry requests, pause during an active job, local speech gates, rate limits, timeouts, and isolated worktrees that preserve a dirty source checkout. Real helper-process stalls also verify bounded enumeration, partial copy, and receipt writes, advancing heartbeats, local work during cloud failure, late child-process reaping, and recovery without duplicate dispatch. Malformed report ID types reject safely while preserving the original.
- 4 packaging/configuration tests pass. Xcode target discovery resolves included xcconfig identities, excludes extensions and dependency samples, rejects ambiguous repository mappings, and preserves settings on reinstall.
- 33 existing report-inspection and transcription tests pass.
- The dependency-free native companion builds in Debug and Release with Swift 6 checking.

Run the receiver and packaging checks with:

```sh
python3 -m unittest discover -s Tools/MZInbox -p test_inbox.py -v
python3 -m unittest discover -s scripts -p test_inbox_build.py -v
python3 -m unittest discover -s scripts -p 'test_bug_report_*.py' -v
swift build --package-path Tools/MZInboxMac -c release
```

## Historical manual checks

Earlier local checks exercised a read-only Codex investigation in a disposable
repository, duplicate-scan behavior, status receipts, native pause/resume controls,
and reopening an ad-hoc-signed companion. These are historical local results;
private report identifiers, agent session identifiers, routes, and diagnostic
artifacts are intentionally omitted from the public guide.

A previous iCloud folder-access timeout was resolved by reselecting both folders
in Settings. This did not change the executable or prove cross-device transfer.
See [the setup guide](report-inbox.md) for the folder-selection procedure.

The original geometric artwork was introduced during open-source preparation.
Regenerating it verifies packaging, independently of these earlier UI checks.

## Physical-device boundary

The final phone-to-Mac acceptance check requires importing the shortcut on an iPhone, choosing the Incoming folder during setup, and sharing a report from an installed app. Mac execution and local status receipts do not establish cross-device iCloud arrival or Share Sheet behavior on that phone.

The companion is locally ad-hoc signed. It is not a notarized public release and is not distributed through TestFlight or the App Store.
