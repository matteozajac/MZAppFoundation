# MZAppFoundation

Private Swift infrastructure for Mateusz's Apple apps: typed analytics, injectable purchases, Sentry diagnostics, Firebase Analytics, Pulse, and developer tools. Version 0.3.1 pins Firebase to 12.19.2 and preserves native Xcode synchronized source groups during local-target setup. It includes the iOS screen/audio bug reporting introduced in 0.3.0, with a Ladybug console action and local Mac transcription tooling.

Feature code uses `import MZAppFoundation`. A setup-managed bootstrap chooses local or live adapters. Simulator app targets link Pulse without RevenueCat/Sentry/Firebase Analytics. The standalone core package has no third-party dependencies.

- [Bug reporting and platform support](docs/bug-reporting.md)
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

Open `MZFoundationSamples.xcodeproj`: choose `FoundationLocal` or `FoundationVisionLocal` for simulators. Device schemes compile live adapters, but samples contain no provider credentials and do not create remote resources. Sample purchases are explicitly simulated.

The repository contains both manifests: root for app integration, `Packages/Core` for dependency-free core tests, sharing the same core source files. Core APIs are independent of Pulse, Firebase, Sentry and RevenueCat types. v0.x is an evolving private interface; pin a tested version per app.
