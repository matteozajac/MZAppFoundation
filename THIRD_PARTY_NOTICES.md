# Third-party notices and provenance

Audit snapshot: 2026-10-21.

## Scope of the project license

[LICENSE](LICENSE) grants the MIT license for original MZAppFoundation material owned by Mateusz Zając. It does not relicense external SDKs, Apple artwork, or copied material whose redistribution rights have not been established. The maintainer has confirmed the redistribution rights for the reporting implementation described below. The Inbox artwork was replaced during preparation.

The Swift packages below are referenced dependencies, not vendored source in this repository. Local `.build/checkouts` and downloaded artifacts are build inputs. They are not part of the source distribution. This inventory links to upstream license texts rather than reproducing licenses for dependencies that are not shipped here.

An application, combined binary, source bundle, or release containing dependencies needs the licenses, copyright notices, attribution, and any source-availability information required by the components it actually distributes. This file alone is not a complete license payload for such a release.

## Complete SwiftPM resolved inventory

The root `Package.swift` declares four direct dependencies. The root `Package.resolved` contains 14 entries, including transitive entries. The initial 16-entry snapshot was checked against matching local checkout license files. After reconciling to the existing 0.6.2 release, the six changed pins were checked separately at their immutable upstream revisions; the unchanged entries retain that initial evidence. The formerly resolved Abseil and gRPC binary wrappers are absent from this graph. The links below use those immutable revisions. “Direct” refers to the root manifest; “Transitive” means resolved through another package.

| Package identity | Version | Relationship | Primary license; qualifications below | Pinned upstream license |
| --- | --- | --- | --- | --- |
| `app-check` | 12.0.0 | Transitive | Apache-2.0 | [LICENSE](https://github.com/google/app-check/blob/c7eb17e5545f36e43dc50e70da09c2e999714e16/LICENSE) |
| `firebase-ios-sdk` | 13.0.0 | Direct | Apache-2.0; component notices also apply | [LICENSE](https://github.com/firebase/firebase-ios-sdk/blob/1c35b9453868cea1ecdf9f112b5b23b8b6343854/LICENSE) |
| `google-ads-on-device-conversion-ios-sdk` | 3.7.0 | Transitive | Apache-2.0 | [LICENSE](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk/blob/0208e2681ec81f8a9c81084696f60fcce26cb7ee/LICENSE) |
| `googleappmeasurement` | 13.0.1 | Transitive | Apache-2.0 | [LICENSE](https://github.com/google/GoogleAppMeasurement/blob/1a3546fb9189292e9d64db9e72add7a286c0f85a/LICENSE) |
| `googledatatransport` | 10.1.1 | Transitive | Apache-2.0 | [LICENSE](https://github.com/google/GoogleDataTransport/blob/ba3358d3c3dbae8ef230b58a46b97ad65e84e974/LICENSE) |
| `googleutilities` | 8.1.4 | Transitive | Apache-2.0 with MIT component | [LICENSE](https://github.com/google/GoogleUtilities/blob/cc31f5ed464b111f877ce8554cbef4455d410d91/LICENSE) |
| `gtm-session-fetcher` | 5.3.1 | Transitive | Apache-2.0 | [LICENSE](https://github.com/google/gtm-session-fetcher/blob/724a52eea6329b7e12d3ad8300d76ca9f3895fcc/LICENSE) |
| `interop-ios-for-google-sdks` | 101.0.0 | Transitive | Apache-2.0 | [LICENSE](https://github.com/google/interop-ios-for-google-sdks/blob/040d087ac2267d2ddd4cca36c757d1c6a05fdbfe/LICENSE) |
| `leveldb` | 1.22.5 | Transitive | BSD-3-Clause | [LICENSE](https://github.com/firebase/leveldb/blob/a0bc79961d7be727d258d33d5a6b2f1023270ba1/LICENSE) |
| `nanopb` | 2.30910.1 | Transitive | zlib | [LICENSE.txt](https://github.com/firebase/nanopb/blob/3851d94a41890dea16dc3db34caf60e585cb4163/LICENSE.txt) |
| `promises` | 2.4.1 | Transitive | Apache-2.0 | [LICENSE](https://github.com/google/promises/blob/f4a19a3c313dc2616c70bb49d29a799fb16be837/LICENSE) |
| `pulse` | 5.2.1 | Direct | MIT, Alexander Grebenyuk | [LICENSE.md](https://github.com/kean/Pulse/blob/14383871aa232bc846d637db45e952adc03d2987/LICENSE.md) |
| `purchases-ios` | 5.94.0 | Direct | MIT, RevenueCat, Inc. | [LICENSE](https://github.com/RevenueCat/purchases-ios/blob/1152c719f7b35f86d16a2d0053aba9d26972a962/LICENSE) |
| `sentry-cocoa` | 9.30.1 | Direct | MIT with additional component terms, including APSL-2.0 | [LICENSE.md](https://github.com/getsentry/sentry-cocoa/blob/4f135c52afeeb1d6937eb93824c7ec1cddcaa372/LICENSE.md) |

The root Firebase dependency declares `traits: []`, disabling the unused Firestore trait and removing the Abseil/gRPC wrapper packages from this resolved graph. The root's core and UI targets use `Packages/Core/Sources`. The standalone `Packages/Core/Package.swift` and `Tools/MZInboxMac/Package.swift` declare no external package dependencies.

## Additional component terms

These findings come from license files, aggregate notices, and source headers at the pinned revisions, not just repository license labels.

- **Sentry:** [THIRD_PARTY_NOTICES.md](https://github.com/getsentry/sentry-cocoa/blob/4f135c52afeeb1d6937eb93824c7ec1cddcaa372/THIRD_PARTY_NOTICES.md) identifies KSCrash and Yandex code under MIT, fishhook-derived code under BSD-3-Clause, and Apple-originated SentryCrash portions under APSL-2.0. The APSL headers occur in `Sources/SentryCrash/Recording/Tools/SentryCrashObjCApple.h` and `SentryCrashMach-O.c`. An executable distribution containing APSL-covered code requires the source-availability notice and acquisition information described in APSL section 2.3; modifications can create additional duties. This does not automatically place unrelated MZAppFoundation code under APSL.
- **Other Sentry headers:** `Sources/Sentry/include/SentryCPU.h` and `SentryCompiler.h` carry Apple/WebKit BSD-2-Clause notices. `SentryThreadState.hpp` identifies LLVM-derived code under Apache-2.0 with the [LLVM exception](https://llvm.org/LICENSE.txt). These are additional to the components enumerated in Sentry's main notices file.
- **GoogleUtilities:** `third_party/IsAppEncrypted/LICENSE` is MIT, copyright Landon J. Fuller. It is used by the production Environment component; its notice is also appended to the root license.
- **Firebase component notices:** [CoreOnly/NOTICES](https://github.com/firebase/firebase-ios-sdk/blob/1c35b9453868cea1ecdf9f112b5b23b8b6343854/CoreOnly/NOTICES) aggregates multiple products. `Crashlytics/LICENSE` includes Hewlett-Packard/libunwind MIT terms. `FirebaseDatabase/LICENSE` includes FImmutableSortedDictionary/MIT, Wrap-leveldb/MIT, and SocketRocket/Apache-2.0 with ISC and IBM notices. `FirebaseSharedSwift/LICENSE` and `FirebaseSharedSwift/Sources/third_party/FirebaseDataEncoder/LICENSE` include Apache-2.0 with Swift's runtime-library exception. `Firestore/LICENSE` includes nlohmann JSON/MIT and FirestoreEncoder/Apache terms with that exception. Use the actual component's full notices when distributing it.
- **Firestore provenance gap:** RE2 and Chromium attribution also occurs in Firestore source headers, including `Firestore/third_party/re2/util/utf.h`, `Firestore/core/src/util/no_destructor.h`, and `md5.cc`. The vendored directories do not supply all referenced standalone RE2/Chromium license texts. Complete those notices if redistributing the affected component or source.
- **gRPC/BoringSSL:** Firebase 13.0.0's aggregate `CoreOnly/NOTICES` identifies BoringSSL-GRPC under Apache-2.0. Its gRPC section scopes BSD-3-Clause to listed podspec/templates and MPL-2.0 to `etc/roots.pem`. The Abseil/gRPC binary-wrapper packages are absent from this resolved graph, and these aggregate notices do not establish that gRPC or its certificate bundle is shipped by this package's selected Analytics products. If distributing MPL-covered material, preserve its notices and provide the source availability/acquisition information required by [MPL section 3.2](https://www.mozilla.org/en-US/MPL/2.0/). Verify the actual selected component before producing a combined binary or source distribution.

### Which dependencies apply

A resolved package or downloaded framework is not proof that a product links or distributes it. In the audited manifest:

- The default `MZAppFoundation` product uses Pulse/PulseUI. `MZAppFoundationUI` and `MZAppFoundationReporting` have no external package dependency.
- `MZAppFoundationLive` adds RevenueCat and Sentry. Individual adapter products select their respective SDKs.
- The Firebase adapter selects `FirebaseCore` and `FirebaseAnalyticsCore` on iOS. That chain uses GoogleAppMeasurementCore, GoogleUtilities, nanopb, and Promises. It does not select GoogleAppMeasurementIdentitySupport or GoogleAdsOnDeviceConversion.
- App Check, GoogleDataTransport, GTMSessionFetcher, interop, and LevelDB are present in the resolved inventory but outside that selected Firebase Core/Analytics chain. Firestore and Database component terms do not become shipment obligations merely because their sources exist in a checkout.

The pinned GoogleAppMeasurement and GoogleAdsOnDeviceConversion license files are Apache-2.0. Firebase's pinned aggregate notices also identify FirebaseAnalytics, GoogleAdsOnDeviceConversion, and GoogleAppMeasurement under Apache-2.0. No separate proprietary EULA was found in the inspected package files or available extracted artifacts. Binary-only delivery is not, by itself, evidence of a proprietary license. Hosted service use remains subject to the applicable [Firebase](https://firebase.google.com/terms) and [Google Analytics](https://marketingplatform.google.com/about/analytics/terms/) agreements.

### Audit limits

The initial 0.5.1 audit had extracted FirebaseAnalytics, FirebaseFirestoreInternal, GoogleAppMeasurement, GoogleAppMeasurementIdentitySupport, and GoogleAdsOnDeviceConversion artifacts available. They contained no additional license, EULA, or notice files. The corresponding Sentry, gRPC, and Abseil binary artifacts recorded in the initial workspace metadata were absent locally. The 0.6.2 delta review checked source licenses/notices at immutable revisions; it did not download or validate new binary artifacts. Archive downloads, checksum revalidation, app linkage, and a distributable application's complete notice payload were not verified by this source audit.

Test/build-only material was distinguished from production sources: GoogleUtilities' CocoaHTTPServer fixtures, nanopb generator/schema/CMake helpers, Firebase's Travis helper, and explicitly excluded BoringSSL test/build support do not establish obligations for unrelated shipped runtime code.

## Reporting source provenance

[The historical reporting validation record](https://github.com/matteozajac/MZAppFoundation/blob/0326b4aa18ce3a978e4f6e36cee532e69facaada/docs/bug-reporting-validation.md) identifies JoinOurDay's `iOS/Packages/BugReporter` as the origin of the reporting implementation. The Foundation implementation entered Git in commit `cd94ea9`, authored by Mateusz Zając.

On 2026-10-21, maintainer Mateusz Zając confirmed that he has the required rights from JoinOurDay for this open-source release. This records the maintainer's confirmation and resolves the previously noted redistribution-rights blocker. The reporting code is included under this repository's MIT license; the origin reference is provenance, not a runtime dependency.

## Original MZ Inbox artwork

`Tools/MZInboxMac/Artwork/AppIcon.png`, `AppIcon.icns`, and `RabbitTemplate.png`
are original geometric rabbit artwork generated by
[`scripts/create_inbox_icon.swift`](scripts/create_inbox_icon.swift), covered by
the repository MIT license. The generator draws its own paths and does not load
or extract system glyphs, Apple emoji, screenshots, or third-party artwork.
See the [artwork source notes](Tools/MZInboxMac/Artwork/README.md).

The initial untracked icons had been rendered from a private Apple/Shortcuts
glyph without recorded redistribution permission. Those three files and their
generator were replaced during open-source preparation. Old copies remain only
in private local T3 checkpoint refs, not in ordinary branch/tag history; do not
publish those refs or distribute an unfiltered workspace archive.

The phone shortcut separately chooses a built-in Shortcuts glyph by numeric
identifier; it does not embed the exported Apple artwork in this source tree.
Apple-generated signed shortcut output is excluded from the source distribution.
The generator code's MIT license does not grant rights to Apple-generated output.
No external image, audio, video, font, model weight, or archive was identified as
vendored in the intended source distribution after this replacement. System-symbol
API calls refer to platform resources rather than bundled image copies.

## Development tools and separately installed programs

`scripts/requirements.txt` pins PyYAML 6.0.3. Its installed distribution's `licenses/LICENSE` is MIT, copyright Ingy döt Net and Kirill Simonov.

`scripts/Gemfile` pins xcodeproj 1.27.0 (MIT), nkf 0.2.0 (BSD-2-Clause), and base64 0.3.0 (Ruby license or BSD-2-Clause). A temporary isolated Bundler resolution used for this audit also installed atomos 0.1.3, CFPropertyList 3.0.8, claide 1.1.0, colored2 3.1.2, and nanaimo 0.4.0 (MIT), plus rexml 3.4.4 (BSD-2-Clause). Their actual installed license files were inspected. This is a dated development-tool snapshot, not a committed Ruby lockfile or a claim that later resolutions will be identical. These tool implementations are not vendored.

The transcription and inbox tools invoke separately installed programs, including whisper.cpp, FFmpeg/ffprobe, and the configured agent CLI. No speech model weights or copies of those executables were found in the inspected source distribution. Xcode, Apple frameworks, XcodeGen, Python, Ruby, and separately installed tools retain their own terms. Check those terms and any model license if bundling them in a future release.

## Keeping this inventory current

When dependencies, copied code, assets, or distribution contents change, recheck the complete resolved graph and actual license/notice files at the selected revisions. Preserve upstream notices with copied or vendored material. For app releases, determine the components actually included and supply their required notices and source information; a lockfile inventory cannot substitute for that verification.
