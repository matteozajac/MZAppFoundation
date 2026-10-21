import SwiftUI

@MainActor
struct JobDetailView: View {
    let model: InboxModel
    let job: InboxJob
    @State private var routeRequest: RouteEditRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(job.title).font(.title.bold()).textSelection(.enabled)
                Label(job.statusTitle, systemImage: job.symbol).font(.headline)
                if let syncError = job.statusSyncError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Phone status is waiting to sync", systemImage: "icloud.slash")
                        Text(syncError).font(.callout).textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow { Text("App").foregroundStyle(.secondary); Text(job.appName).textSelection(.enabled) }
                    if let identifier = job.bundleIdentifier {
                        GridRow { Text("Bundle").foregroundStyle(.secondary); Text(identifier).textSelection(.enabled) }
                    }
                    if let date = job.receivedDate {
                        GridRow { Text("Received").foregroundStyle(.secondary); Text(date, format: .dateTime) }
                    }
                    GridRow { Text("Report").foregroundStyle(.secondary); Text(job.reportID ?? job.id).textSelection(.enabled) }
                }
                if let error = job.error, !error.isEmpty {
                    Label("This report needs attention", systemImage: "exclamationmark.circle").font(.headline)
                    Text(error).textSelection(.enabled)
                }
                if job.status == "waiting_for_route" {
                    Text("Choose the local project for this app. Future reports will use the same project automatically.")
                    Button("Connect to Project", systemImage: "folder.badge.plus") {
                        let existing = model.configuration.routes.first { $0.bundleIdentifier == job.bundleIdentifier }
                        routeRequest = RouteEditRequest(
                            route: existing ?? AppRoute(bundleIdentifier: job.bundleIdentifier ?? "", name: job.appName, repository: ""),
                            originalIdentifier: existing?.bundleIdentifier
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                FlowActions(model: model, job: job)
                if let path = job.worktreePath {
                    Text("Prepared project: \(path)").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if job.status == "fix_ready" {
                    Text("The agent prepared a fix in a separate worktree. Open the result to review the changes and checks.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $routeRequest) { request in
            RouteEditor(model: model, route: request.route) { route in
                try await model.saveRoute(route, replacing: request.originalIdentifier)
            }
        }
    }
}

@MainActor
private struct FlowActions: View {
    let model: InboxModel
    let job: InboxJob

    var body: some View {
        HStack {
            if let path = job.resultPath {
                Button("Open Result", systemImage: "doc.text") { model.openPath(path) }
                    .buttonStyle(.borderedProminent)
            }
            if let path = job.jobDirectory {
                Button("Open Evidence", systemImage: "folder") { model.openPath(path) }
            }
            if let path = job.worktreePath {
                Button("Open Project", systemImage: "hammer") { model.openPath(path) }
            }
            if job.canRetry {
                Button(model.retryingJobID == job.id ? "Retrying…" : "Retry Report", systemImage: "arrow.clockwise") {
                    Task { await model.retry(job) }
                }
                .disabled(model.retryingJobID != nil)
            }
        }
    }
}
