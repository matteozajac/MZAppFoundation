# MZAppFoundation 0.6.1

Retains 0.6.0's explicit Firebase reuse, injected Sentry filtering, asynchronous
Pulse metadata repair and exact SDK pins. Pulse remains 5.2.1, Sentry 9.30.1,
RevenueCat 5.94.0 and Firebase's canonical SwiftPM release 13.0.0.

Splits a reporting-test fixture expression into typed subexpressions so the
minimum supported Xcode toolchain can compile the same contract suite as Xcode 27.
The 0.6.0 CI run passed core/tooling tests, every sample build and all 16 adapter
tests, then stopped on that fixture's type-checking timeout. Runtime implementation
is unchanged. VERSION, compiled metadata, setup defaults and samples select 0.6.1.

The 0.6.1 validation receipt will be recorded after CI completes. Device provider
and purchase acceptance is separate from these build/test checks.
