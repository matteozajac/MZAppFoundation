# Verification

Use this guide to reproduce checks for the checkout and host app you are integrating. It is a command reference, not a blanket certification of this revision. Historical release/validation notes describe their own dated environments and should not be read as current device or provider evidence.

## Inspect the checkout

From the repository root:

```sh
cat VERSION
swift --version
swift package dump-package
swift package --package-path Packages/Core dump-package
```

The root manifest declares optional vendor dependencies. The nested core/UI manifest has no third-party dependencies. `VERSION`, the manifests, resolved package files, and generated `FoundationVersion.swift` describe different parts of the build; check that they agree before recording a release's evidence. A newer Git tag does not imply this checkout uses it.

## Core and script tests

```sh
swift test --package-path Packages/Core
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements.txt
.venv/bin/python -m unittest discover -s scripts -p 'test_*.py'
```

The Swift tests run without a host app or vendor SDK dependency graph. They cover core routing, schema/redaction rules, purchases/mocks, developer access, diagnostics, and UI model contracts; they do not exercise provider delivery or device sensors.

Script fixtures cover setup, build metadata, archive inspection, transcription orchestration, and inbox packaging logic. Some fixtures need macOS tools, XcodeGen, Ruby/xcodeproj, or FFmpeg/ffprobe; read test skips and failures instead of treating missing prerequisites as passing coverage. Native-project setup fixtures require the Ruby dependencies in `scripts/Gemfile`. Use `BUNDLE_GEMFILE=scripts/Gemfile bundle exec .venv/bin/python -m unittest discover -s scripts -p 'test_*.py'` when using a bundle-managed installation. Transcription orchestration fixtures use a test speech executable; they do not establish real model accuracy.

The [README example](../README.md#dependency-free-core-example) is a separate executable that can be built with `swift run --package-path FoundationDemo` from its parent directory. It verifies the documented public initializer/event calls without remote engines.

## Sample builds and tests

Install XcodeGen 2.44+ and Xcode with the target SDK, then generate the sample project:

```sh
xcodegen generate --spec Samples/project.yml
xcodebuild -list -project Samples/MZFoundationSamples.xcodeproj
```

The schemes are defined in `Samples/project.yml`. `FoundationLocal` and `FoundationVisionLocal` use simulator platforms; `FoundationMacLocal` targets macOS. `FoundationDevice` and `FoundationVisionDevice` compile compatibility provider compositions without supplying provider credentials. Unit/UI schemes include `FoundationAdapterTests`, `FoundationReportingTests`, `FoundationDeveloperTests`, and `FoundationMacUITests`.

For an unsigned iOS simulator build:

```sh
xcodebuild -project Samples/MZFoundationSamples.xcodeproj \
  -scheme FoundationLocal -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath output/verification/ios-local \
  CODE_SIGNING_ALLOWED=NO build
```

For tests, select an installed simulator rather than the generic build destination:

```sh
xcodebuild -showdestinations -project Samples/MZFoundationSamples.xcodeproj \
  -scheme FoundationLocal
xcodebuild -project Samples/MZFoundationSamples.xcodeproj \
  -scheme FoundationLocal -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath output/verification/ios-tests test
```

Replace `SIMULATOR_UUID` with an available destination ID. Use a matching platform and scheme for visionOS or macOS. Test/build success establishes only the selected configuration and environment; record the toolchain, destination, configuration, revision, result bundle, and skipped tests.

## Local binary inspection

The binary checker accepts a built iOS/visionOS `.app` path and requires Pulse symbols. For the simulator build above:

```sh
python3 scripts/audit_binary.py \
  output/verification/ios-local/Build/Products/Debug-iphonesimulator/FoundationLocal.app \
  --local
```

`--local` fails when selected RevenueCat, Sentry, or Firebase Analytics names appear in scanned executable symbols or bundled filenames. Dependency resolution/download is separate from linkage. This check is a heuristic over the supplied artifact, not a complete security or dependency audit. It does not inspect macOS's `Contents/MacOS` layout, prove physical-device behavior, or establish backend delivery. A stripped artifact without detectable Pulse symbols also fails.

## Host-app integration

Using a configured host app and installed setup prerequisites:

```sh
.venv/bin/python scripts/setup.py inspect --app-root ../MyApp
.venv/bin/python scripts/setup.py verify --app-root ../MyApp
```

Replace `../MyApp` with the intended app directory. These modes read `.mzappfoundation/config.json` by default; `--config` accepts another file. `inspect` inventories vendor imports and product-definition candidates. `verify` checks generated/local wiring and rejects unresolved direct vendor imports. Neither command compiles the host app or proves provider provisioning. `apply` mutates the project and belongs to the reviewed [integration workflow](integration.md#optional-setup-tooling).

Build/test all affected targets separately, inspect local artifacts, and exercise the host's entrypoint, settings, preferences, purchase policy, and reporter. Preserve backend dependencies still required outside the telemetry adapters.

## Unreleased inbox tooling

```sh
swift build --package-path Tools/MZInboxMac
python3 -m unittest discover -s Tools/MZInbox -p 'test_*.py'
```

The worker tests use synthetic reports, temporary local Git repositories, and a fake Codex executable. They do not deliver a report from an iPhone over iCloud or run a real investigation. The separate `python3 scripts/verify_inbox.py --live` command explicitly invokes an installed/authenticated Codex CLI for a real read-only investigation and writes a local receipt. The script requires `--live`; omitting it is an error, not an offline test. See the [Mac receiver README](../Tools/MZInboxMac/README.md) for setup.

## Evidence to collect separately

Physical-device tests are needed for shake/responder behavior, microphone permission, voice capture, ReplayKit lifecycle, and phone-to-Mac transfer. Real purchase/restore and revocation behavior need the app's catalog and appropriate store environment. Analytics and diagnostics delivery need confirmation in the target provider project; symbolication needs the matching archive/symbol upload and provider readback.

Keep source review, fixture tests, simulator tests, artifact inspection, device checks, provider readbacks, and release state distinct. Sample builds, mock purchases, generated identity metadata, submitted verification events, or an inbox agent result do not substitute for those checks.
