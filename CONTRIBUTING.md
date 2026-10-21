# Contributing

Bug reports, focused fixes, documentation improvements, and tests are welcome. Please follow the [code of conduct](CODE_OF_CONDUCT.md). Report vulnerabilities through the [security policy](SECURITY.md), rather than a public issue or pull request.

## Before changing code

Start from the current `main` branch and check existing issues and pull requests. For a substantial API or dependency change, describe the problem and proposed behavior in an issue first. Small fixes can go straight to a pull request.

Keep the core package independent of vendor SDKs. Put provider-specific types and initialization in their adapters, and preserve the distinction between local and live compositions. Tests and examples should use synthetic data and example identifiers. Do not provision cloud projects, use production credentials, or exercise real purchases as part of a contribution.

## Development environment

Use macOS with Xcode and Swift 6.2.3 or newer selected as the active developer toolchain. The manifests target macOS 15+, iOS 26+, and visionOS 26+; testing iOS or visionOS changes also requires the corresponding Xcode SDK and simulator runtime. The CI workflow records its selected Xcode, Python, and Ruby versions in [`.github/workflows/validate.yml`](.github/workflows/validate.yml).

For Python tooling, use Python 3.13 and install the pinned requirements in a virtual environment. Setup fixture tests also require XcodeGen (at least 2.44.0, as declared by the sample project) and Ruby with Bundler. Use a maintained Ruby installation rather than relying on macOS's bundled Ruby.

Run these commands from the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r scripts/requirements.txt
brew install xcodegen
bundle install --gemfile scripts/Gemfile
```

`bundle install` installs development tooling; a resulting local lockfile is not a dependency update to submit automatically. If selecting a nondefault Ruby executable, set `RUBY` to it so the Python setup fixtures use the same Ruby as Bundler.

## Checks

Run the SDK-free core tests:

```sh
swift test --package-path Packages/Core
```

Run the setup, metadata, report-tooling, and packaging tests with the virtual environment active:

```sh
BUNDLE_GEMFILE=scripts/Gemfile bundle exec python3 -m unittest discover -s scripts -p 'test_*.py'
```

For MZ Inbox worker or companion changes, also run:

```sh
python3 -m unittest discover -s Tools/MZInbox -p 'test_*.py'
swift build --package-path Tools/MZInboxMac -c release
```

The worker tests use synthetic archives, temporary Git repositories, and a fake agent executable. They do not need a live agent account or iCloud inbox. Building the companion alone does not install it, start a worker, or enable login items. Check dependency and source provenance in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before packaging or distributing it.

For changes to provider adapters, reporting, or SwiftUI presentation, build and exercise the affected sample targets as well. The sample project is generated from `Samples/project.yml`; the validation workflow contains the current sample schemes and build commands. Core tests alone do not validate those targets. Describe the device or simulator, OS, configuration, and actions you actually tested; distinguish compilation from runtime behavior and live provider delivery.

## Pull requests

Explain the concrete problem, resulting behavior, and relevant checks. Add a regression test when behavior changes and update affected documentation. If a check cannot run, name the missing prerequisite or failure instead of claiming it passed.

Keep generated build output, personal paths, account configuration, report archives, recordings, and credentials out of the change. Use a small synthetic reproduction rather than uploading a real bug-report ZIP, log database, screenshot, or voice note that may contain private information.

New dependencies or copied code and assets need an identifiable source and redistribution permission. Preserve applicable notices and update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), including the complete resolved dependency inventory when pins change. Access to a private source repository is not permission to publish its contents.

Original contributions are accepted under this project's [MIT license](LICENSE). By submitting a contribution, you confirm that you have the right to contribute it under those terms; identify any separately licensed material explicitly. No contributor license agreement is required.
