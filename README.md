# MZAppFoundation

Private Swift infrastructure for Mateusz's Apple apps: typed analytics, injectable purchases, Sentry diagnostics, Firebase Analytics, Pulse, and developer tools. Version **0.6.0** adds explicit reuse of app-initialized Firebase, injectable Sentry event filtering, updated provider SDKs, and precise binary-isolation checks. Protected developer settings and optional provider adapters remain available across iOS, visionOS, and macOS.

Feature code uses `import MZAppFoundation`. A setup-managed bootstrap chooses independent RevenueCat, Sentry, and iOS Firebase Analytics products when configured; existing Live/Firebase umbrellas remain compatible. Simulator app targets link Pulse without those SDKs. The standalone core/UI package has no third-party dependencies. Shared developer preference/link contracts remain app-scoped and do not change telemetry permission or purchase verification.

- [Bug reporting and platform support](docs/bug-reporting.md)
- [Developer settings, provider diagnostics, and shared access/link contracts](docs/developer-settings.md)
- [0.6.0 release notes](docs/release-0.6.0.md)
- [0.5.1 release notes](docs/release-0.5.1.md)
- [0.5.0 release notes](docs/release-0.5.0.md)
- [Developer settings validation](docs/developer-settings-validation.md)
- [Integration and build profiles](docs/integration.md)
- [Existing-app migration guide](docs/migration.md)
- [Setup skill](skills/mz-app-foundation-setup/SKILL.md)
- [Verification evidence](docs/verification.md)

## Get started

```sh
git clone git@github.com:matteozajac/MZAppFoundation.git
cd MZAppFoundation
python3 scripts/install_skill.py
```

Then ask Codex: “Use $mz-app-foundation-setup to configure this app.” The installer symlinks the canonical skill into `~/.codex/skills` and records the checkout revision under `~/.codex/skill-installations`. Update the checkout to an explicit reviewed tag and rerun the installer to record an update. Remove the symlink to uninstall; keep the repo if apps use it locally.

```sh
swift test --package-path Packages/Core
cd Samples
xcodegen generate
```

Open `MZFoundationSamples.xcodeproj`: choose `FoundationLocal` or `FoundationVisionLocal` for simulators, or `FoundationMacLocal` for native macOS. Device schemes compile compatibility adapters, but samples contain no provider credentials and do not create remote resources. Sample purchases are explicitly simulated. The settings component presents an iOS sheet or registered macOS/visionOS sidebar window; developer access gates every destination.

The repository contains both manifests: root for app integration, `Packages/Core` for dependency-free core/UI, sharing the same core source files. Core APIs are independent of Pulse, Firebase, Sentry and RevenueCat types. `VERSION` and the metadata generator supply compiled library versions; app build stamps record source identities and resolved packages without pretending to verify live delivery. v0.x is an evolving private interface; pin a tested version per app. Setup defaults to 0.6.0; use `package_path` for a local checkout. Explicitly pinned 0.3.1 integrations retain compatible generation until individually upgraded.
