# Structured logging validation — 2026-09-26

Version 0.2.0 adds vendor-independent error snapshots, caller locations and one diagnostics route. The setup and app-logging skills were validated with the skill-creator validator and installed as repository-backed symlinks.

- Core: 22 tests pass, covering original error identity, signed codes, bounded nested/cyclic causes, privacy, cancellation, stack provenance, caller forwarding and single-entry routing.
- Adapter tests: Pulse persistence preserves readable metadata and source; Sentry's pure event mapper retains exception chains and stack provenance without initializing transport.
- iOS and visionOS: the sample UI test opens Logs, selects a real captured error and verifies cause and operation metadata in the details inspector.
- iOS screenshot was visually checked for readable technical text, source location and separate reporting-stack frames. Local artifact: `output/logging/ios-error-details.png` (ignored).
- visionOS UI assertions pass; the test screenshot captures the underlying window, so it is not visual proof of the console sheet.

Reporting stacks describe the capture boundary, not the original throw site. Remote Sentry delivery/symbolication and physical-device behavior are not proven by these checks. Pulse 5.2.1's metadata whitespace behavior is covered by the adapter preservation test; see integration.md for the implementation tradeoff.
