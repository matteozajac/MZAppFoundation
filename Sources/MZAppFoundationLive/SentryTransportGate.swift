import Foundation
import Synchronization

final class SentryTransportGate: NSObject, URLSessionTaskDelegate {
    private struct TaskReference: Sendable { weak var task: URLSessionTask? }
    private struct State: Sendable {
        var revoked = false
        var tasks: [TaskReference] = []
    }
    private let state = Mutex(State())
    var allowsDelivery: Bool { state.withLock { !$0.revoked } }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let allowed = state.withLock { state in
            guard !state.revoked else { return false }
            state.tasks.removeAll { $0.task == nil }
            state.tasks.append(TaskReference(task: task))
            return true
        }
        if !allowed { task.cancel() }
    }
    func revoke() {
        let tasks = state.withLock { state in
            state.revoked = true
            let tasks = state.tasks.compactMap(\.task)
            state.tasks.removeAll()
            return tasks
        }
        for task in tasks { task.cancel() }
    }
}
