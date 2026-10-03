import MZAppFoundation
import SwiftUI

/// Protected diagnostics, with compact navigation on iOS and a sidebar on desktop/spatial platforms.
public struct FoundationSettingsView: View {
    private let services: AppServices
    private let bundle: Bundle
    private let pages: [FoundationDeveloperPage]
    private let keyboardShortcutSections: [FoundationKeyboardShortcutSection]
    @State private var selection: FoundationSettingsRoute?
    @State private var issuesOnly = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    public init(services: AppServices, bundle: Bundle = .main, pages: [FoundationDeveloperPage] = [],
                keyboardShortcutSections: [FoundationKeyboardShortcutSection] = []) {
        self.services = services; self.bundle = bundle
        self.keyboardShortcutSections = keyboardShortcutSections
        var ids = Set<String>()
        self.pages = pages.filter { ids.insert($0.id).inserted }
    }

    public var body: some View {
        Group {
            if services.developerOptions.isEnabled {
                #if os(macOS) || os(visionOS)
                NavigationSplitView {
                    overview.navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
                } detail: {
                    if let selection { destination(selection) }
                    else {
                        ContentUnavailableView("App Foundation", systemImage: "square.stack.3d.up",
                            description: Text("Select a provider or developer tool in the sidebar."))
                    }
                }
                #else
                NavigationStack {
                    overview.navigationDestination(for: FoundationSettingsRoute.self) { destination($0) }
                }
                #endif
            }
        }
        .onChange(of: services.developerOptions.isEnabled, initial: true) { _, enabled in
            if !enabled {
                selection = nil
                dismiss()
                #if os(macOS) || os(visionOS)
                dismissWindow(id: FoundationSettingsScene.id)
                #endif
            }
        }
        .accessibilityIdentifier("mz.foundation.settings")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { services.developerOptions.refreshExpiration() }
        }
    }

    private var overview: some View {
        overviewList
            .navigationTitle("Foundation")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    @ViewBuilder private var overviewList: some View {
        #if os(macOS) || os(visionOS)
        List(selection: $selection) { overviewRows }
        #else
        List { overviewRows }
        #endif
    }

    @ViewBuilder private var overviewRows: some View {
            Section {
                Label("App Foundation", systemImage: "square.stack.3d.up").font(.title2.bold())
                DiagnosticValueRow("MZAppFoundation", value: FoundationVersion.current)
                    .accessibilityIdentifier("mz.foundation.version")
                Toggle("Only show provider issues", isOn: $issuesOnly)
                    .accessibilityIdentifier("mz.foundation.issuesOnly")
            }
            if let issue = services.foundationDiagnostics.bootstrapIssue {
                Section("Startup") {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("mz.foundation.bootstrapIssue")
                }
            }
            providerSection
            if !services.additionalDiagnosticSections.isEmpty {
                Section("App services") {
                    ForEach(services.additionalDiagnosticSections) { section in
                        if !issuesOnly || section.findings.contains(where: { $0.severity != .info }) {
                            NavigationLink(value: FoundationSettingsRoute.section(section.id)) {
                                VStack(alignment: .leading) {
                                    Text(section.title)
                                    Text(section.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section("Diagnostics") {
                route("Build information", image: "hammer", value: .build)
                route("Startup history", image: "power", value: .startup)
                route("Telemetry counters", image: "chart.bar", value: .telemetry)
                route("Session timeline", image: "clock", value: .timeline)
                route("Export diagnostics", image: "square.and.arrow.up", value: .export)
            }
            if !pages.isEmpty {
                Section("App developer tools") {
                    ForEach(pages) { page in
                        route(page.title, image: page.systemImage, value: .page(page.id))
                    }
                }
            }
            Section("Developer access") {
                route("Keyboard Shortcuts", image: "keyboard", value: .shortcuts)
                route("Links and QR codes", image: "link", value: .links)
                route("Access duration", image: "timer", value: .access)
                if services.configuration.environment == .local {
                    route("Local QA scenarios", image: "testtube.2", value: .qa)
                }
                DiagnosticValueRow("Activation", value: services.developerOptions.activationSource.rawValue)
                Button("Disable developer options", role: .destructive) { services.developerOptions.setEnabled(false) }
                    .accessibilityIdentifier("mz.foundation.disable")
            }
    }

    private var providerSection: some View {
        Section {
            ForEach(services.providerSnapshots) { snapshot in
                if !issuesOnly || snapshot.findings.contains(where: { $0.severity != .info }) {
                    NavigationLink(value: FoundationSettingsRoute.provider(snapshot.provider)) {
                        FoundationProviderRow(snapshot: snapshot)
                    }
                    .accessibilityIdentifier("mz.foundation.provider." + snapshot.provider.rawValue)
                }
            }
            if issuesOnly && services.providerSnapshots.allSatisfy({ $0.findings.allSatisfy { $0.severity == .info } }) {
                Text("No provider issues for the declared expectations.").foregroundStyle(.secondary)
            }
        } header: { Text("Providers") } footer: {
            Text("Configuration, runtime policy and SDK submission are separate from confirmed backend receipt.")
        }
    }

    private func route(_ title: String, image: String, value: FoundationSettingsRoute) -> some View {
        NavigationLink(value: value) { Label(title, systemImage: image) }
    }

    @ViewBuilder private func destination(_ route: FoundationSettingsRoute) -> some View {
        if services.developerOptions.isEnabled {
            switch route {
            case .provider(let provider): FoundationProviderDetailsView(services: services, provider: provider)
            case .section(let id):
                if let section = services.additionalDiagnosticSections.first(where: { $0.id == id }) {
                    FoundationAppServiceView(section: section)
                }
            case .page(let id):
                if let page = pages.first(where: { $0.id == id }) { page.makeView().navigationTitle(page.title) }
            case .build: FoundationBuildView(services: services)
            case .startup: FoundationStartupView(services: services)
            case .telemetry: FoundationTelemetryView(services: services)
            case .timeline: FoundationTimelineView(services: services)
            case .links: FoundationDeepLinkView(services: services, bundle: bundle)
            case .export: FoundationExportView(services: services)
            case .qa: FoundationQAView(services: services)
            case .access: FoundationAccessView(options: services.developerOptions)
            case .shortcuts: FoundationKeyboardShortcutsView(options: services.developerOptions, sections: keyboardShortcutSections)
            }
        }
    }
}
