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

    #if os(iOS)
    /// Adds local bug reporting to the existing console, with screen and voice capture.
    func appDeveloperTools(_ options: DeveloperOptions, reporting: DeveloperReporting) -> some View {
        modifier(DeveloperToolsModifier(options: options, reporting: reporting))
    }
    #endif
}

private struct DeveloperToolsModifier: ViewModifier {
    @Bindable var options: DeveloperOptions
    #if os(iOS)
    var reporting: DeveloperReporting? = nil
    @State private var window = ReportingWindow()
    @Environment(\.scenePhase) private var scenePhase
    #endif
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
            .background(ShakeReceiver(onShake: { options.requestConsole() }, onWindow: {
                window.value = $0
                synchronizeReporting()
            }).allowsHitTesting(false))
            .onChange(of: options.consoleRequested) { _, _ in synchronizeReporting() }
            .onChange(of: options.isEnabled, initial: true) { _, _ in synchronizeReporting() }
            .onChange(of: scenePhase) { _, phase in
                // ReplayKit's consent dialog briefly makes the scene inactive.
                if phase != .inactive { synchronizeReporting() }
            }
            .onDisappear { reporting?.coordinator.update(developerMode: options.isEnabled, isActive: false) }
            .sheet(isPresented: Binding(get: { isPresented && reporting == nil },
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

    #if os(iOS)
    private func synchronizeReporting() {
        guard let reporting else { return }
        let active = window.value?.windowScene?.activationState == .foregroundActive
        reporting.coordinator.update(developerMode: options.isEnabled, isActive: active)
        if options.consoleRequested, options.isEnabled, active, let origin = window.value {
            reporting.present(from: origin)
            options.dismissConsole()
        }
    }
    #endif
}

#if os(iOS)
import UIKit

@MainActor private final class ReportingWindow {
    weak var value: UIWindow?
}

/// A scoped responder in the hosting controller's chain; no global UIWindow override or swizzling.
private struct ShakeReceiver: UIViewControllerRepresentable {
    let onShake: @MainActor () -> Void
    let onWindow: @MainActor (UIWindow?) -> Void
    func makeUIViewController(context: Context) -> ShakeController { ShakeController(onShake: onShake, onWindow: onWindow) }
    func updateUIViewController(_ controller: ShakeController, context: Context) {
        controller.onShake = onShake
        controller.onWindow = onWindow
    }

    final class ShakeController: UIViewController {
        var onShake: @MainActor () -> Void
        var onWindow: @MainActor (UIWindow?) -> Void
        init(onShake: @escaping @MainActor () -> Void, onWindow: @escaping @MainActor (UIWindow?) -> Void) {
            self.onShake = onShake
            self.onWindow = onWindow
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }
        override var canBecomeFirstResponder: Bool { true }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
            onWindow(view.window)
        }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake, view.window?.windowScene?.activationState == .foregroundActive { onShake() }
            super.motionEnded(motion, with: event)
        }
    }
}
#endif
