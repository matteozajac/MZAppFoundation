import Foundation
import Testing
@testable import MZAppFoundation

@MainActor struct ProviderDiagnosticsTests {
    private let configuration = AppConfiguration(bundleIdentifier: "com.example.app", urlScheme: "example", environment: .local)

    @Test func absentAdaptersStillShowEveryOptionalProviderAndMissingFirebaseFile() throws {
        let bundle = try #require(Bundle(identifier: "com.apple.Foundation"))
        let snapshots = FoundationDiagnostics(bundle: bundle).snapshots(configuration: configuration, preferences: .init())
        #expect(snapshots.map(\.provider) == FoundationProvider.allCases)
        #expect(snapshots.allSatisfy { $0.runtime == .notLinked && $0.sdkVersion == nil })
        #expect(snapshots.first?.configuration == .missing)
    }

    @Test func malformedAndMismatchedFirebaseFilesAreVisibleWithoutLeakingSecrets() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a plist".utf8).write(to: file)
        #expect(FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: file.path).state == .invalid)
        var plist = ["PROJECT_ID": "target-project", "GOOGLE_APP_ID": "1:123:ios:abc", "GCM_SENDER_ID": "123",
                     "BUNDLE_ID": "wrong.app", "API_KEY": "secret-must-never-appear", "PRIVATE_FIELD": "private"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file)
        let mismatch = FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: file.path)
        #expect(mismatch.state == .invalid)
        #expect(mismatch.details.contains { $0.value == "target-project" })
        #expect(!String(reflecting: mismatch).contains("secret-must-never-appear"))
        #expect(!mismatch.details.contains { $0.id == "API_KEY" || $0.id == "PRIVATE_FIELD" })
        plist["BUNDLE_ID"] = configuration.bundleIdentifier
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file)
        #expect(FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: file.path).state == .configured)
        try FileManager.default.removeItem(at: file)
        #expect(FirebaseConfigurationInspection.inspect(bundleIdentifier: configuration.bundleIdentifier, path: file.path).state == .missing)
    }

    @Test func snapshotsReadCurrentPreferencesAndNeverChangeDeveloperOrDeliveryState() {
        let store = UserDefaults(suiteName: "mz.diagnostics.tests." + UUID().uuidString)!
        let inventory = FoundationDiagnostics().replacing(.sentry) { context in
            ProviderSnapshot(provider: .sentry, sdkVersion: "test", configuration: .configured,
                runtime: .suppressed, delivery: context.delivery(configured: true, preference: context.preferences.diagnostics),
                details: [.init("preference", label: "Preference", value: String(context.preferences.diagnostics))])
        }
        let remote = RecordingDiagnosticsEngine(delivery: .remote)
        let services = AppServices(configuration: configuration,
            telemetry: Telemetry(configuration: configuration, schema: .init(events: [:]), diagnostics: [remote]),
            logger: RecordingLogger(), purchases: UnavailablePurchases(),
            developerOptions: DeveloperOptions(configuration: configuration, defaults: store), foundationDiagnostics: inventory)
        #expect(services.providerSnapshots.last?.details.first?.value == "true")
        services.telemetry.updatePreferences(.init(analytics: false, diagnostics: false))
        #expect(services.providerSnapshots.last?.details.first?.value == "false")
        #expect(services.providerSnapshots.last?.delivery == .runtimeBlocked)
        #expect(!remote.enabled && remote.issues.isEmpty)
        #expect(store.object(forKey: DeveloperOptions.preferenceKey) == nil)
        #expect(services.purchases.cachedState == nil)
    }
}
