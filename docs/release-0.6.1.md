# MZAppFoundation 0.6.1

Retains 0.6.0's explicit Firebase reuse, injected Sentry filtering, asynchronous
Pulse metadata repair and exact SDK pins. Pulse remains 5.2.1, Sentry 9.30.1,
RevenueCat 5.94.0 and Firebase's canonical SwiftPM release 13.0.0.

Splits a reporting-test fixture expression into typed subexpressions so the
minimum supported Xcode toolchain can compile the same contract suite as Xcode 27.
The 0.6.0 CI run passed core/tooling tests, every sample build and all 16 adapter
tests, then stopped on that fixture's type-checking timeout. Runtime implementation
is unchanged. VERSION, compiled metadata, setup defaults and samples select 0.6.1.

Validation on 2026-10-10: [Xcode 26.6 CI passed](https://github.com/matteozajac/MZAppFoundation/actions/runs/38070663175)
on runtime/setup source commit `4e90dc6773b7dce25cfa150a1fd2d2cdddc923a2`:
52 core tests, 64 tooling tests, all iOS/visionOS local/device builds, 16 adapter
contracts, 34 reporting contracts and 4 developer-presentation contracts. The
release follow-up changes only these notes. The same core/tooling checks passed
locally with Xcode 27; Roamline consumes the final exact release tag.

Repeated CI runs of the release notes commit exposed a hosted-test race: the
first Command-D test sent its action before the installed root controller's
appearance callback supplied a first responder. The follow-up test fixture waits
for the key window and the production responder, and stops immediately if that
readiness requirement fails. Hosted tests use the app's library symbols instead
of linking duplicate static library copies. All four presentation tests passed
three consecutive local runs after that correction. This follow-up changes only
tests, sample test linkage and these notes; the published 0.6.1 runtime is unchanged.

Device provider and purchase acceptance is separate from these build/test checks.
