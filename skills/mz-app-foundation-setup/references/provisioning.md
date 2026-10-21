# Provider provisioning and verification

Use this workflow only for providers included in the user's setup request, with the app owner's connected tools, supported CLIs or dashboard. `setup.py` handles local project wiring; it does not authenticate or create remote resources. Local logging, reporting and developer tools do not require provider provisioning. Do not create provider projects for the included demonstration apps.

## Discovery and resume

Resolve bundle ID, app name, platform, developer organization/team and existing configuration from the app. Check existing authenticated connections without printing credentials; this package supplies no default provider account, connection name, Analytics account/property, Sentry organization or RevenueCat project. Look up exact resource identities before creating anything. Reuse resources when both identity and ownership match. If multiple plausible organizations remain, resolve that choice before remote writes while continuing independent local work. Reuse current session authorization.

Keep administrative credentials in the user's tool-managed credential store, OS credential storage or CI secrets. Never put OAuth tokens, API secrets, refresh tokens, private keys or passwords in manifests, receipts, source, logs or chat. Public SDK keys, DSNs and Firebase client configuration must belong to the selected app; an authenticated account alone does not establish that match.

Keep `.mzappfoundation/provisioning.json` as a non-secret receipt of provider project/app IDs, verified bundle IDs, catalog mappings, outstanding setup, and readback time. Re-read remote state on resume; the receipt is a pointer, not proof that configuration is current. Check for an existing resource after a timeout before retrying creation. Stop repeated mutations after one retry and report the unresolved provider step while continuing independent local work.

## Firebase

Prefer available Firebase connector operations for listing projects/apps and getting SDK configuration, then creation when needed. The [Firebase CLI](https://firebase.google.com/docs/cli) fallback provides `projects:list`, `apps:list`, `projects:create`, `apps:create`, and `apps:sdkconfig`; inspect each command's current help. Bind project-scoped commands to the selected project explicitly. Choose a Google Analytics account/property owned by this app's organization; do not reuse another app's property as a default.

1. Reuse/create the Firebase project and Apple app with the exact bundle ID. Download its actual `GoogleService-Info.plist`; validate `BUNDLE_ID`, `GOOGLE_APP_ID`, and `PROJECT_ID` before integrating.
2. Inspect whether Google Analytics is enabled and linked to the intended GA account/property. Configure the link in Firebase Console when no suitable connected API is available. Do not create an arbitrary Analytics account. Record analytics as pending until the link is confirmed.
3. Configure automatic screen reporting and ad/IDFV collection off. Runtime analytics follows the independent app delivery preference. Do not disable Firebase globally if the app uses backend products.
4. On visionOS, omit Firebase Analytics. Do not deploy a relay or provision a Firestore database for this scope.
5. Provider verification requires a physical-device test event and readback in the selected property's DebugView/realtime view; simulator events must not be used as proof.

Sources: https://firebase.google.com/docs/projects/api/workflow_set-up-and-manage-project
https://firebase.google.com/docs/ios/setup
https://firebase.google.com/docs/analytics/configure-data-collection
https://firebase.google.com/docs/ios/learn-more

## Sentry

Prefer available Sentry tools/API. Discover the current organization, teams and projects. Reuse or create an Apple-platform project in the intended team. Obtain its public client DSN, verify project ID/organization and integrate it. Support self-hosted Sentry when explicitly configured.

Configure CI environment `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN`, and an explicit `SENTRY_CLI_VERSION`. Install that CLI version as `sentry-cli` on CI's PATH. The foundation's `scripts/upload_symbols.py` is copied by setup to the app's `.mzappfoundation/Generated/upload_symbols.py` and invoked as an Xcode archive build phase, using Xcode's build environment rather than command-line arguments. Use the CI provider's secret API/CLI without echoing token values. Check `sentry-cli debug-files upload --help`; the script uses `--wait` and verifies UUIDs through the project debug-files API. For a self-hosted service, configure `SENTRY_URL` consistently for the CLI and helper.

Before symbol upload verify bundle release identity, executable/dSYM UUID equality, provider project identity, and configured CLI version. The helper only processes iOS/visionOS device archives (`PLATFORM_NAME=iphoneos` or `xros`, non-Debug, `ACTION=install`); it skips macOS, simulator, Debug and non-archive builds. Configure a separate supported symbol-upload workflow if macOS delivery is requested. Verify a deliberate crash only in a dedicated device diagnostic run; do not crash an ordinary user's app as part of setup. Record separately whether symbols and crash ingestion were verified.

Sources: https://docs.sentry.io/api/projects/create-a-new-project/
https://docs.sentry.io/platforms/apple/guides/ios/dsym/
https://docs.sentry.io/api/projects/list-a-projects-debug-information-files/

## RevenueCat

Prefer connected RevenueCat tools. Discover exact projects/apps with listing and get operations before create operations. Register an App Store app with the exact bundle ID; reuse public Apple SDK key and existing credentials. Dashboard-only store credential setup may use computer use, with secrets sourced from secure storage.

When no confirmed product definitions exist: register/reuse project/app, wire the public SDK key, and mark `catalog: absent`. Do not create empty/default offerings, mock real products, or invented entitlements.

When products exist:

1. Find app constants/configuration, current App Store product records, entitlement identifiers, offering/package mappings, and any existing RevenueCat configuration. Source-code references alone do not prove store products exist.
2. Reconcile RevenueCat product records to verified App Store product IDs. Create missing RevenueCat records without creating/changing App Store prices or products.
3. Reuse/create entitlements and attach confirmed products. Reuse/create the intended offering, packages and product assignments. Do not change the current offering unless app configuration requires it; explain any unresolved conflict.
4. Read back the full mapping and public SDK key's app identity. Record app, product, entitlement, offering and package IDs in the receipt. Do not log customer IDs, receipts or transaction data.
5. Device purchase, pending approval, cancellation, restore, refund/revocation and identity transitions need sandbox/TestFlight testing. A configured catalog or mock test is not purchase verification.

Sources: https://www.revenuecat.com/docs/projects/overview
https://www.revenuecat.com/docs/offerings/overview
https://www.revenuecat.com/docs/api-v2

## No release side effects

Setup does not upload a build, distribute TestFlight, submit for review, change store pricing, or publish privacy statements. Flag required privacy disclosure updates for the app's own release workflow. Do not claim compliance from SDK settings.
