#if os(iOS)
import MZAppFoundationUI
import SwiftUI
import UIKit

/// Wraps the scene's existing root controller, preserving its SwiftUI tree and
/// environment. Modal responders forward through that root to this container.
struct DeveloperToolsAnchor: UIViewControllerRepresentable {
    let isEnabled: @MainActor () -> Bool
    let onOpen: @MainActor () -> Void
    let onWindow: @MainActor (UIWindow?) -> Void

    func makeUIViewController(context: Context) -> AnchorController {
        AnchorController(isEnabled: isEnabled, onOpen: onOpen, onWindow: onWindow)
    }
    func updateUIViewController(_ controller: AnchorController, context: Context) {
        controller.isEnabled = isEnabled
        controller.onOpen = onOpen
        controller.onWindow = onWindow
        controller.updateResponder()
    }

    final class AnchorController: UIViewController {
        var isEnabled: @MainActor () -> Bool
        var onOpen: @MainActor () -> Void
        var onWindow: @MainActor (UIWindow?) -> Void
        private weak var responder: DeveloperResponderController?

        init(isEnabled: @escaping @MainActor () -> Bool, onOpen: @escaping @MainActor () -> Void,
             onWindow: @escaping @MainActor (UIWindow?) -> Void) {
            self.isEnabled = isEnabled
            self.onOpen = onOpen
            self.onWindow = onWindow
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Move the existing root after UIKit completes its appearance pass.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.attach()
            }
        }

        private func attach() {
            guard let window = view.window, let root = window.rootViewController else { return }
            if let existing = root as? DeveloperResponderController {
                responder = existing
            } else {
                let container = DeveloperResponderController(content: root)
                responder = container
                window.rootViewController = container
            }
            updateResponder()
            onWindow(window)
        }

        func updateResponder() {
            responder?.isEnabled = isEnabled
            responder?.onOpen = onOpen
        }
    }
}

final class DeveloperResponderController: UIViewController {
    private let content: UIViewController
    var isEnabled: @MainActor () -> Bool = { false }
    var onOpen: @MainActor () -> Void = {}

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeFirstResponder: Bool { true }
    override var performsActionsWhilePresentingModally: Bool { true }
    override var childForStatusBarStyle: UIViewController? { content }
    override var childForStatusBarHidden: UIViewController? { content }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { content.supportedInterfaceOrientations }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Supply a responder for hardware keys on screens with no focused input.
        // Preserve any responder the existing app has already selected.
        if !hasFirstResponder(in: content), !content.becomeFirstResponder() { becomeFirstResponder() }
    }

    private func hasFirstResponder(in controller: UIViewController) -> Bool {
        if controller.isFirstResponder || hasFirstResponder(in: controller.view) { return true }
        if let presented = controller.presentedViewController, hasFirstResponder(in: presented) { return true }
        return controller.children.contains(where: hasFirstResponder)
    }

    private func hasFirstResponder(in view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains(where: hasFirstResponder)
    }

    private var canOpen: Bool { isEnabled() && view.window?.windowScene?.activationState == .foregroundActive }

    override var keyCommands: [UIKeyCommand]? {
        guard canOpen else { return super.keyCommands }
        let shortcut = FoundationKeyboardShortcutCatalog.developerConsole
        let command = UIKeyCommand(title: shortcut.title, action: #selector(openDeveloperConsole),
                                   input: String(shortcut.key.character), modifierFlags: .command)
        return (super.keyCommands ?? []) + [command]
    }

    @objc func openDeveloperConsole() { if canOpen { onOpen() } }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(openDeveloperConsole) { return canOpen }
        return super.canPerformAction(action, withSender: sender)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake, canOpen { onOpen() }
        else { super.motionEnded(motion, with: event) }
    }
}
#endif
