#if os(iOS)
import UIKit

/// A temporary scene-local presentation surface. The app's existing sheets and
/// alerts stay attached to their original window and regain focus on dismissal.
@MainActor public final class DeveloperOverlayWindow {
    public let presenter: UIViewController
    private let window: UIWindow
    private weak var previousKeyWindow: UIWindow?

    public init?(from origin: UIWindow) {
        guard let scene = origin.windowScene, scene.activationState == .foregroundActive else { return nil }
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow) ?? origin
        presenter = UIViewController()
        presenter.view.backgroundColor = .clear
        window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.rootViewController = presenter
        window.makeKeyAndVisible()
    }

    public func close() {
        let restoreFocus = window.isKeyWindow
        window.isHidden = true
        window.rootViewController = nil
        if restoreFocus, let previousKeyWindow, !previousKeyWindow.isHidden,
           previousKeyWindow.windowScene === window.windowScene,
           previousKeyWindow.windowScene?.activationState == .foregroundActive {
            previousKeyWindow.makeKey()
        }
    }
}
#endif
