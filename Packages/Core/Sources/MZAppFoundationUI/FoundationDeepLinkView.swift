import CoreImage
import MZAppFoundation
import SwiftUI

struct FoundationDeepLinkView: View {
    let services: AppServices
    let bundle: Bundle
    @State private var input = ""
    @State private var inspection: DeveloperDeepLinkInspection?

    var body: some View {
        List {
            Section {
                DiagnosticValueRow("App host", value: services.developerOptions.linkHost)
                DiagnosticValueRow("Shared scheme registered", value: registered ? "Yes" : "No · register mzappfoundation")
                Text("The shared scheme can open any installed app that registers it. Prefer this app's unique scheme when several apps are installed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let link = appLink(.enable) { linkSection("Enable this app", url: link, showQR: true) }
            if let link = appLink(.disable) { linkSection("Disable this app", url: link, showQR: false) }
            if let shared = DeveloperDeepLink.url(for: .enable, host: services.developerOptions.linkHost) {
                linkSection("Shared enable link", url: shared, showQR: false)
            }
            Section {
                TextField("Paste a developer link", text: $input, axis: .vertical)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("mz.foundation.link.input")
                Button("Inspect without opening") {
                    inspection = DeveloperDeepLink.inspect(input, host: services.developerOptions.linkHost,
                                                           legacyScheme: services.configuration.urlScheme)
                }
                .accessibilityIdentifier("mz.foundation.link.inspect")
                if let inspection {
                    DiagnosticValueRow("Result", value: inspection.accepted ? "Accepted" : "Rejected")
                    if let action = inspection.action { DiagnosticValueRow("Action", value: action.rawValue) }
                    if let format = inspection.format { DiagnosticValueRow("Format", value: format.rawValue) }
                    if let reason = inspection.rejectionReason { DiagnosticValueRow("Reason", value: reason.rawValue) }
                }
            } header: { Text("Dry run") } footer: {
                Text("Inspecting a link does not change developer access or launch another app. Pasted links are not included in exports.")
            }
        }
        .navigationTitle("Links and QR codes")
    }

    private func appLink(_ action: DeveloperDeepLink.Action) -> URL? {
        DeveloperDeepLink.url(for: action, host: services.developerOptions.linkHost, scheme: services.configuration.urlScheme)
    }
    private var registered: Bool {
        let entries = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return entries.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains { $0.lowercased() == DeveloperDeepLink.scheme } }
    }
    private func linkSection(_ title: String, url: URL, showQR: Bool) -> some View {
        Section(title) {
            Text(url.absoluteString).textSelection(.enabled)
            HStack {
                Button("Copy", systemImage: "doc.on.doc") { DiagnosticClipboard.copy(url.absoluteString) }
                    .buttonStyle(.bordered)
                ShareLink(item: url).buttonStyle(.bordered)
            }
            if showQR { DeveloperLinkQRCode(url: url) }
        }
    }
}

private struct DeveloperLinkQRCode: View {
    let url: URL
    @State private var code: CGImage?
    var body: some View {
        Group {
            if let code {
                Image(decorative: code, scale: 1)
                    .interpolation(.none).resizable().scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .padding(16).background(.white)
                    .accessibilityLabel("QR code for this app's developer enable link")
            }
        }
        .task(id: url) { code = qrImage() }
    }
    private func qrImage() -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
