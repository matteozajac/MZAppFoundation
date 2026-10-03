#if os(iOS)
import MZAppFoundation
import SwiftUI
import UIKit

struct FoundationReportingView: View {
    let options: DeveloperOptions
    let reporting: DeveloperReporting
    var showsRecordingSettings = true
    @State private var anchor = FoundationReportingAnchor()

    var body: some View {
        List {
            Section {
                Button(showsRecordingSettings ? "Open bug reporter" : "Open Pulse console", systemImage: "ladybug") {
                    guard options.isEnabled, let window = anchor.window else { return }
                    reporting.present(from: window)
                }
                .accessibilityIdentifier("mz.foundation.report.open")
                Text("Capture a report with optional logs, recording and a redacted foundation diagnostics snapshot.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if showsRecordingSettings {
                DeveloperReportingSettings(reporting: reporting)
            }
        }
        .background(FoundationReportingWindow { anchor.window = $0 }.allowsHitTesting(false))
    }
}

@MainActor private final class FoundationReportingAnchor { weak var window: UIWindow? }

private struct FoundationReportingWindow: UIViewRepresentable {
    let onWindow: @MainActor (UIWindow?) -> Void
    func makeUIView(context: Context) -> AnchorView { AnchorView(onWindow: onWindow) }
    func updateUIView(_ view: AnchorView, context: Context) { view.onWindow = onWindow }

    final class AnchorView: UIView {
        var onWindow: @MainActor (UIWindow?) -> Void
        init(onWindow: @escaping @MainActor (UIWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() { super.didMoveToWindow(); onWindow(window) }
    }
}
#endif
