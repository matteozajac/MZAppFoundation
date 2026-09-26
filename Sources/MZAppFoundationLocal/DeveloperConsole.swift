import MZAppFoundation
import PulseUI
import SwiftUI

public struct DeveloperConsole: View {
    private let options: DeveloperOptions
    public init(options: DeveloperOptions) { self.options = options }
    public var body: some View {
        NavigationStack {
            if options.isEnabled { ConsoleView(store: .shared, mode: .logs) }
            else { ContentUnavailableView("Developer mode is off", systemImage: "lock") }
        }
        .accessibilityIdentifier("mz.developer.console")
        .onAppear {
            PulseLogger().log(LogEntry("developer_console_opened", category: "developer"))
        }
    }
}

public struct DeveloperConsoleScene: Scene {
    public static let id = "mzappfoundation.console"
    private let options: DeveloperOptions
    public init(options: DeveloperOptions) { self.options = options }
    public var body: some Scene {
        WindowGroup("Developer Console", id: Self.id) {
            DeveloperConsole(options: options)
                .onDisappear { options.dismissConsole() }
        }
        .defaultSize(width: 800, height: 600)
    }
}

public extension View {
    func appDeveloperTools(_ options: DeveloperOptions) -> some View {
        modifier(DeveloperToolsModifier(options: options))
    }
}

private struct DeveloperToolsModifier: ViewModifier {
    @Bindable var options: DeveloperOptions
    #if os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    func body(content: Content) -> some View {
        let isPresented = options.consoleRequested && options.isEnabled
        return content
            .onOpenURL { url in
                if options.handle(url) {
                    #if os(visionOS)
                    if options.isEnabled { options.requestConsole() }
                    #endif
                }
            }
            #if os(iOS)
            .background(ShakeReceiver { options.requestConsole() }.allowsHitTesting(false))
            .sheet(isPresented: Binding(get: { isPresented },
                                        set: { if !$0 { options.dismissConsole() } })) {
                DeveloperConsole(options: options)
            }
            #elseif os(visionOS)
            .task { options.launchSpatialConsole() }
            .onChange(of: options.consoleRequested, initial: true) { _, requested in
                if requested && options.isEnabled { openWindow(id: DeveloperConsoleScene.id) }
                else { dismissWindow(id: DeveloperConsoleScene.id) }
            }
            #endif
    }
}

#if os(iOS)
import UIKit

/// A scoped responder in the hosting controller's chain; no global UIWindow override or swizzling.
private struct ShakeReceiver: UIViewControllerRepresentable {
    let onShake: @MainActor () -> Void
    func makeUIViewController(context: Context) -> ShakeController { ShakeController(onShake: onShake) }
    func updateUIViewController(_ controller: ShakeController, context: Context) { controller.onShake = onShake }

    final class ShakeController: UIViewController {
        var onShake: @MainActor () -> Void
        init(onShake: @escaping @MainActor () -> Void) {
            self.onShake = onShake
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }
        override var canBecomeFirstResponder: Bool { true }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake, view.window?.windowScene?.activationState == .foregroundActive { onShake() }
            super.motionEnded(motion, with: event)
        }
    }
}
#endif
