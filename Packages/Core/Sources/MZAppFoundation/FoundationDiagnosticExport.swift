import Foundation

/// An immutable, versioned support snapshot. Raw logs, event values and customer identity have no fields here.
public struct FoundationDiagnosticExport: Codable, Equatable, Sendable {
    public static let maximumBytes = 1_048_576
    public enum ExportError: Error, Sendable { case tooLarge }
    public struct App: Codable, Equatable, Sendable {
        public let bundleIdentifier: String
        public let version: String
        public let build: String
        public let environment: AppEnvironment
    }
    public struct DeveloperAccess: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let activationSource: String
        public let expiresAt: Date?
    }
    public struct Timeline: Codable, Equatable, Sendable {
        public let entries: [DiagnosticTimelineEntry]
        public let capacity: Int
        public let discardedEntries: Int
    }

    public let format: String
    public let schemaVersion: Int
    public let capturedAt: Date
    public let app: App
    public let foundationVersion: String
    public let buildMetadata: FoundationBuildMetadata
    public let providers: [ProviderSnapshot]
    public let startupRecords: [ProviderStartupRecord]
    public let preferences: DeliveryPreferences
    public let developerAccess: DeveloperAccess
    public let counters: TelemetryCounters
    public let timeline: Timeline
    public let purchases: PurchaseDiagnosticsSnapshot?
    public let additionalSections: [FoundationDiagnosticSection]

    @MainActor init(services: AppServices) {
        format = "mzappfoundation-diagnostics"; schemaVersion = 1; capturedAt = .now
        let configuration = services.configuration
        app = App(bundleIdentifier: Self.safeIdentifier(configuration.bundleIdentifier) ?? "Unavailable",
                  version: Self.safeIdentifier(configuration.version) ?? "Unavailable",
                  build: Self.safeIdentifier(configuration.build) ?? "Unavailable", environment: configuration.environment)
        foundationVersion = FoundationVersion.current
        buildMetadata = Self.redacted(services.foundationDiagnostics.buildMetadata)
        providers = services.providerSnapshots.map(Self.redacted)
        startupRecords = services.foundationDiagnostics.startupRecords.prefix(100).map { record in
            ProviderStartupRecord(provider: record.provider, stage: record.stage, status: record.status,
                                  code: Self.safeCode(record.code),
                                  message: "\(record.stage.rawValue): \(record.status.rawValue)", recordedAt: record.recordedAt)
        }
        preferences = services.telemetry.preferences
        developerAccess = DeveloperAccess(enabled: services.developerOptions.isEnabled,
            activationSource: services.developerOptions.activationSource.rawValue,
            expiresAt: services.developerOptions.expiresAt)
        counters = services.telemetry.counters
        timeline = Timeline(entries: services.telemetry.timeline.entries,
                            capacity: services.telemetry.timeline.capacity,
                            discardedEntries: services.telemetry.timeline.discardedEntries)
        purchases = services.foundationDiagnostics.purchaseDiagnostics?().map(Self.redacted)
        additionalSections = services.foundationDiagnostics.sections(configuration: configuration, preferences: preferences)
            .prefix(25).compactMap(Self.redacted)
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ExportError.tooLarge }
        return data
    }

    public var text: String {
        var lines = ["App Foundation diagnostics (schema \(schemaVersion))", "Captured: \(capturedAt.ISO8601Format())",
                     "App: \(app.bundleIdentifier) \(app.version) (\(app.build))", "Environment: \(app.environment.rawValue)",
                     "Foundation: \(foundationVersion)", "Developer access: \(developerAccess.enabled ? "enabled" : "disabled") (\(developerAccess.activationSource))",
                     "Analytics preference: \(preferences.analytics)", "Diagnostics preference: \(preferences.diagnostics)"]
        if let revision = buildMetadata.appRevision { lines.append("App revision: \(revision)") }
        if let revision = buildMetadata.foundationRevision { lines.append("Foundation revision: \(revision)") }
        if let channel = buildMetadata.buildChannel { lines.append("Build channel: \(channel)") }
        if let date = buildMetadata.buildDate { lines.append("Build date: \(date.ISO8601Format())") }
        if let modified = buildMetadata.appWorkingTreeModified { lines.append("App working tree modified: \(modified)") }
        if let modified = buildMetadata.foundationWorkingTreeModified { lines.append("Foundation working tree modified: \(modified)") }
        lines.append("Build evidence: \(buildMetadata.provenance)")
        lines += buildMetadata.resolvedPackageVersions.sorted { $0.key < $1.key }.map { "Package \($0.key): \($0.value)" }
        for provider in providers {
            lines.append("\(provider.provider.name): \(provider.summary); expectation \(provider.expectation.rawValue); SDK \(provider.sdkVersion ?? "not linked")")
            lines += provider.details.map { "  \($0.label): \($0.value)" }
            for (scope, identity) in [("expected", provider.identityAudit.expected), ("supplied", provider.identityAudit.supplied), ("running", provider.identityAudit.running)] {
                if let identity {
                    let values = [identity.name, identity.projectID, identity.appID, identity.organization].compactMap { $0 }
                    lines.append("  \(scope) identity: \(values.joined(separator: " · "))")
                }
            }
            lines += provider.findings.map { "  \($0.severity.rawValue): \($0.code)" }
        }
        lines += startupRecords.map { "Startup \($0.provider?.rawValue ?? "composition"): \($0.stage.rawValue) \($0.status.rawValue) [\($0.code)]" }
        for (name, values) in [("Analytics", counters.analytics), ("Diagnostics", counters.diagnostics), ("Breadcrumbs", counters.breadcrumbs)] {
            lines.append("\(name): \(values.attempts) attempts; \(values.schemaRejected) rejected; \(values.filteredProperties) properties filtered; \(values.preferenceBlocked) preference blocks; \(values.runtimeBlocked) runtime blocks; \(values.recordedLocal) local records; \(values.submittedRemote) remote submissions; \(values.ignored) ignored; \(values.failed) failures")
        }
        if let purchases {
            lines.append("Purchase verification: \(purchases.verification.rawValue)")
            lines += purchases.entitlements.map { "Entitlement \($0.entitlementID): \($0.isActive ? "active" : "inactive"); \($0.verification.rawValue); sandbox \($0.isSandbox.map(String.init) ?? "unknown")" }
            lines += purchases.offerings.map { "Offering \($0.offeringID): \($0.productIDs.joined(separator: ", "))" }
        }
        for section in additionalSections {
            lines.append("\(section.title) [\(section.id)]")
            lines += section.details.map { "  \($0.label): \($0.value)" }
            lines += section.findings.map { "  \($0.severity.rawValue): \($0.code)" }
        }
        lines.append("Timeline: \(timeline.entries.count) retained; \(timeline.discardedEntries) discarded")
        lines += timeline.entries.map { "\($0.timestamp.ISO8601Format()) \($0.category.rawValue): \($0.event.rawValue) \($0.status.rawValue)" }
        lines.append("Adapter submission does not prove backend receipt. Event payloads, credentials, receipts, and customer identities are excluded.")
        return lines.joined(separator: "\n")
    }

    private static func redacted(_ snapshot: ProviderSnapshot) -> ProviderSnapshot {
        var result = snapshot
        result.sdkVersion = snapshot.sdkVersion.flatMap(safeIdentifier)
        result.versionSource = snapshot.versionSource.flatMap(safeName)
        result.explanation = "Technical configuration only; remote verification is separate."
        let detailIDs: Set<String> = ["projectName", "projectID", "appID", "organization", "server", "dsnProject",
            "PROJECT_ID", "GOOGLE_APP_ID", "BUNDLE_ID", "GCM_SENDER_ID", "STORAGE_BUCKET",
            "projectID", "googleAppID", "bundleID", "senderID", "storageBucket", "coreVersion", "analyticsVersion", "qa.scenario"]
        let fileStates: Set<String> = ["Present", "GoogleService-Info.plist missing", "Supplied file missing", "Unreadable or invalid plist"]
        let configurationStates: Set<String> = ["Missing", "Present · hidden", "Invalid · hidden"]
        result.details = snapshot.details.prefix(100).compactMap { detail in
            if detail.id == "file" || detail.id == "fileStatus" {
                guard fileStates.contains(detail.value) else { return nil }
                return .init("configurationFile", label: "Configuration file", value: detail.value)
            }
            if detail.id == "key" || detail.id == "dsn" {
                guard configurationStates.contains(detail.value) else { return nil }
                return .init("configurationStatus", label: "Client configuration", value: detail.value)
            }
            guard detailIDs.contains(detail.id), let value = safeName(detail.value) else { return nil }
            return .init(detail.id == "dsnProject" ? "ingestionProjectID" : detail.id, label: detail.id, value: value)
        }
        result.identityAudit = ProviderIdentityAudit(expected: snapshot.identityAudit.expected.map(redacted),
            supplied: snapshot.identityAudit.supplied.map(redacted), running: snapshot.identityAudit.running.map(redacted),
            ownership: snapshot.identityAudit.ownership)
        result.findings = snapshot.findings.prefix(100).map {
            DiagnosticFinding(code: safeCode($0.code), severity: $0.severity, message: "Review this finding in the developer settings.")
        }
        return result
    }

    private static func redacted(_ identity: ProviderProjectIdentity) -> ProviderProjectIdentity {
        .init(name: identity.name.flatMap(safeName), projectID: identity.projectID.flatMap(safeIdentifier),
              appID: identity.appID.flatMap(safeIdentifier), organization: identity.organization.flatMap(safeIdentifier))
    }

    private static func redacted(_ section: FoundationDiagnosticSection) -> FoundationDiagnosticSection? {
        guard let id = safeIdentifier(section.id), let title = safeName(section.title) else { return nil }
        let details = section.details.filter { section.exportableDetailIDs.contains($0.id) }.prefix(25).compactMap { detail -> ProviderDetail? in
            guard !RedactionPolicy.isSensitive(detail.id), !["apikey", "dsn", "key"].contains(detail.id.lowercased()),
                  let id = safeIdentifier(detail.id), let value = safeName(detail.value) else { return nil }
            return .init(id, label: id, value: value)
        }
        return .init(id: id, title: title, summary: "Only explicitly selected technical fields are exported.", details: details,
                     findings: section.findings.prefix(25).map {
            .init(code: safeCode($0.code), severity: $0.severity, message: "Review this finding in the developer settings.")
        })
    }

    private static func redacted(_ metadata: FoundationBuildMetadata) -> FoundationBuildMetadata {
        let provenance: Set<String> = ["App-supplied build metadata", "Library Package.resolved snapshot; app build is not stamped",
            "App Package.resolved and build source identities", "Library Package.resolved snapshot and build source identities",
            "Build source identities; no Package.resolved was available"]
        return .init(appRevision: metadata.appRevision.flatMap(safeIdentifier), foundationRevision: metadata.foundationRevision.flatMap(safeIdentifier),
              foundationVersion: safeIdentifier(metadata.foundationVersion) ?? FoundationVersion.current,
              buildChannel: metadata.buildChannel.flatMap(safeName), buildDate: metadata.buildDate,
              resolvedPackageVersions: Dictionary(uniqueKeysWithValues: metadata.resolvedPackageVersions.sorted { $0.key < $1.key }.prefix(100).compactMap {
                  guard !RedactionPolicy.isSensitive($0.key), !["apikey", "dsn"].contains($0.key.lowercased()) else { return nil }
                  guard let name = safeIdentifier($0.key), let version = safeIdentifier($0.value) else { return nil }
                  return (name, version)
              }), appWorkingTreeModified: metadata.appWorkingTreeModified, foundationWorkingTreeModified: metadata.foundationWorkingTreeModified,
              provenance: provenance.contains(metadata.provenance) ? metadata.provenance : "Safe build metadata supplied by the host or library")
    }

    private static func redacted(_ snapshot: PurchaseDiagnosticsSnapshot) -> PurchaseDiagnosticsSnapshot {
        .init(provider: snapshot.provider, entitlements: snapshot.entitlements.prefix(100).compactMap {
            guard let entitlement = safeIdentifier($0.entitlementID), let product = safeIdentifier($0.productID) else { return nil }
            return .init(entitlementID: entitlement, productID: product, isActive: $0.isActive, isSandbox: $0.isSandbox,
                         verification: $0.verification, expiresAt: $0.expiresAt)
        }, offerings: snapshot.offerings.prefix(50).compactMap {
            guard let offering = safeIdentifier($0.offeringID) else { return nil }
            return .init(offeringID: offering, isCurrent: $0.isCurrent,
                         productIDs: $0.productIDs.prefix(25).compactMap(safeIdentifier), packageIDs: $0.packageIDs.prefix(25).compactMap(safeIdentifier))
        }, verification: snapshot.verification, requestDate: snapshot.requestDate, lastReceivedAt: snapshot.lastReceivedAt,
              lastOfferingsFetchAt: snapshot.lastOfferingsFetchAt, explanation: "Cached catalog and entitlement verification; customer identity is excluded.")
    }

    private static func safeCode(_ value: String) -> String {
        guard value.range(of: "^[A-Za-z][A-Za-z0-9_.-]{0,127}$", options: .regularExpression) != nil else { return "redacted_code" }
        return safeIdentifier(value) ?? "redacted_code"
    }
    private static func safeIdentifier(_ value: String) -> String? {
        guard value.range(of: "^[A-Za-z0-9_$][A-Za-z0-9_.$:+-]{0,127}$", options: .regularExpression) != nil else { return nil }
        return safeName(value)
    }
    private static func safeName(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 128,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.contains("://"), !value.contains("@"), !value.contains("?"), !value.contains("#"),
              !value.contains("="), !value.contains("\\"), !value.contains("/") else { return nil }
        let lower = value.lowercased()
        guard !["appl_", "goog_", "sk_", "rcb_", "aiza", "bearer "].contains(where: lower.hasPrefix) else { return nil }
        return value
    }
}
