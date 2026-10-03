import MZAppFoundation
import SwiftUI

struct FoundationProviderRow: View {
    let snapshot: ProviderSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.provider.name).font(.headline)
            Text(snapshot.summary).font(.subheadline).foregroundStyle(.secondary)
            if snapshot.expectation != .optional {
                Text(snapshot.expectation == .required ? "Required by app" : "Intentionally unused")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if snapshot.findings.contains(where: { $0.severity != .info }) {
                Label("Configuration needs attention", systemImage: "exclamationmark.triangle").font(.caption)
            }
            if let version = snapshot.sdkVersion {
                Text("SDK " + version).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
