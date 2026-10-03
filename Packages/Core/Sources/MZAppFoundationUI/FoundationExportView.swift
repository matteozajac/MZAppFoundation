import MZAppFoundation
import SwiftUI
import UniformTypeIdentifiers

private struct FoundationDiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct FoundationExportView: View {
    let services: AppServices
    @State private var snapshot: FoundationDiagnosticExport?
    @State private var document = FoundationDiagnosticDocument()
    @State private var contentType = UTType.json
    @State private var exporting = false
    @State private var exportFailed = false

    var body: some View {
        List {
            Section {
                Text("Create a snapshot of this build, provider identity, startup results, counters and the bounded session timeline. Keys, DSNs, user IDs, receipts and event payloads are excluded.")
                Button("Capture current diagnostics", systemImage: "arrow.clockwise") {
                    snapshot = services.diagnosticExport()
                    services.telemetry.timeline.record(.diagnosticsExported, category: .diagnostics, status: .recorded)
                }
                .accessibilityIdentifier("mz.foundation.export.capture")
            }
            if let snapshot {
                Section("Share") {
                    Button("Save JSON", systemImage: "square.and.arrow.up") { prepare(snapshot, type: .json) }
                    Button("Save text", systemImage: "doc.text") { prepare(snapshot, type: .plainText) }
                    Button("Copy text", systemImage: "doc.on.doc") { DiagnosticClipboard.copy(snapshot.text) }
                    ShareLink(item: snapshot.text) { Label("Share text", systemImage: "square.and.arrow.up") }
                }
                Section("Preview") { Text(snapshot.text).font(.caption.monospaced()).textSelection(.enabled) }
            }
            if exportFailed { Text("The diagnostics file could not be saved.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Export diagnostics")
        .fileExporter(isPresented: $exporting, document: document, contentType: contentType,
                      defaultFilename: "foundation-diagnostics") { result in
            if case .failure = result { exportFailed = true }
        }
    }

    private func prepare(_ snapshot: FoundationDiagnosticExport, type: UTType) {
        guard services.developerOptions.isEnabled else { return }
        do {
            document.data = type == .json ? try snapshot.jsonData() : Data(snapshot.text.utf8)
            contentType = type; exportFailed = false; exporting = true
        } catch { exportFailed = true }
    }
}
