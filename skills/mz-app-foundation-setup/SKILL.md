---
name: mz-app-foundation-setup
description: Set up or migrate an Apple app to MZAppFoundation with injectable analytics, RevenueCat purchases, Sentry diagnostics, Firebase Analytics, Pulse, developer deep links, and local builds without heavy SDKs. Provision matching provider resources, integrate XcodeGen or native Xcode projects, and verify repeated setup. Does not publish an app or invent a purchase catalog.
---

# MZAppFoundation setup

The repository containing this skill is the canonical implementation. Resolve symlinks to locate its root (two directories above this file). Read `../../docs/integration.md` before wiring an app and `references/provisioning.md` before provider work. Read `../../docs/migration.md` only when adopting an existing app.

## Outcome

App feature code imports `MZAppFoundation`, with injected package-owned interfaces. Only the bootstrap and app entrypoint import composition/UI modules. Local app targets link the Pulse composition; device targets link live adapters. Standalone core tests use `Packages/Core`, with no external dependencies.

## Workflow

1. Inspect the app's instructions, Git state, project file, target/deployment settings, existing SDK imports and initialization, event schemas, purchase definitions, and provider identities. Do not infer that a similarly named remote project belongs to this app. Preserve app-specific policies and unrelated changes.
2. Create `.mzappfoundation/config.json` using `../../docs/config.example.json`. Existing apps keep their own analytics/diagnostics defaults. New apps default both on, with independent controls. Fill schema entries from real app event definitions; empty schema means no product events are delivered.
3. Run `python3 <repo>/scripts/setup.py inspect --app-root <app>` with dependencies from `scripts/requirements.txt` installed in a virtual environment. Resolve catalog and resource matches using the provisioning reference. Configure providers through connected tools or CLI; use computer use for UI-only steps. Reuse current session authorization and report exact outcomes.
4. Run `setup.py apply`. XcodeGen requires `xcodegen`; native Xcode requires the Ruby gems in `scripts/Gemfile` (use `RUBY` to select a compatible interpreter). Review the generated project changes. For inherited XcodeGen target templates, xcconfigs, extensions, or custom build phases, inspect effective settings; the script cannot safely infer every transitive dependency.
5. Integrate `MZBootstrap.services`, `.appDeveloperTools(services.developerOptions)`, and the visionOS `DeveloperConsoleScene` into the existing app entrypoint. Preserve unrelated deep links, delegates, scenes, and startup behavior. Move vendor-dependent app adapters out of local target membership; replace feature call sites with injected interfaces. App-specific paywall UI and access policy remain app-owned.
6. `setup.py verify` checks source wiring, but does not prove binary isolation. Build/run local iOS/visionOS targets, build device adapters, and use `scripts/audit_binary.py <local.app> --local`. Inspect build logs for compiled vendor targets; resolution/download alone is permitted. Run the core tests and appropriate app behavior tests. Check shake, console window, enable/disable links, purchase recovery and telemetry policy.
7. Run apply again and ensure no unintended diff. Record implemented, configured, built, simulator-verified, device-verified, and provider-verified status separately. Missing credentials, absent products, or unperformed device checks are explicit partial states. Commit/push only the requested repository work.

## Non-obvious constraints

- Public releases include Pulse, but developer mode defaults off. Local/Debug/Internal defaults on; an explicit persisted enable/disable wins. Deep links never change remote delivery or purchase verification.
- Simulator, preview and unit-test paths cannot initialize live providers. Source `#if` guards do not remove linked SDKs: maintain separate local and device target dependencies.
- `MZ_LOCAL` and `MZ_INTERNAL` belong to the app's build settings. Do not assume app compilation flags propagate to Swift packages.
- Firebase v1 covers bootstrap/Analytics only. Preserve app-owned Auth/Firestore/Functions/etc. visionOS has no Firebase Analytics adapter.
- Only declared event/property schema crosses analytics engines. Never put user-authored text, tokens, identifiers, receipts, or raw error descriptions into log messages or diagnostic codes. Local Pulse is not an exemption.
- Instrument network calls explicitly through `InstrumentedSession`; no global proxy. Bodies and query values are omitted. Apps must omit sensitive URL path segments or exclude those calls from instrumentation.
- Administrative keys belong in environment/secure CI storage. RevenueCat public Apple SDK keys, Sentry DSNs, and Firebase app configuration are client configuration, not administrative tokens. Never echo private credentials.
- RevenueCat app registration is allowed without products. Create offerings/packages/entitlements only from confirmed existing app product definitions. Do not invent prices, create store products, or grant real access from mock state.
- Do not bootstrap duplicate Firebase/Sentry/RevenueCat owners. Bootstrap conflicts require reconciliation, not another singleton.
- A successful build does not prove crash delivery, Sentry symbol readback, Firebase collection, or purchase/restore on a physical device.
