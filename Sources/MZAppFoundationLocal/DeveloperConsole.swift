import MZAppFoundation
@_exported import MZAppFoundationUI
import PulseUI
import SwiftUI

/// Standalone Pulse logs. For iOS reports, use `appDeveloperTools(_:reporting:)`
/// so the shared coordinator manages recording, attachments and presentation.
public struct DeveloperConsole: View {
    private let options: DeveloperOptions
    private let onDismiss: (() -> Void)?
    public init(options: DeveloperOptions, onDismiss: (() -> Void)? = nil) {
        self.options = options
        self.onDismiss = onDismiss
    }
    public var body: some View {
        NavigationStack {
            if options.isEnabled {
                #if os(macOS)
                FoundationMacConsole()
                #else
                ConsoleView(store: .shared, mode: .logs)
                    .toolbar {
                        if let onDismiss {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done", action: onDismiss).accessibilityIdentifier("mz.developer.console.close")
                            }
                        }
                    }
                #endif
            }
            else { ContentUnavailableView("Developer mode is off", systemImage: "lock") }
        }
        .accessibilityIdentifier("mz.developer.console")
        .onAppear {
            PulseLogger().log(LogEntry("developer_console_opened", category: "developer"))
        }
    }
}

public struct DeveloperConsoleScene: Scene {
    public static let id = DeveloperOptions.consoleSceneID
    private let options: DeveloperOptions
    public init(options: DeveloperOptions) { self.options = options }
    public var body: some Scene {
        #if os(macOS)
        Window("Developer Console", id: Self.id) {
            DeveloperConsole(options: options).onDisappear { options.dismissConsole() }
        }
        .defaultSize(width: 800, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        #else
        WindowGroup("Developer Console", id: Self.id) {
            DeveloperConsole(options: options)
                .onDisappear { options.dismissConsole() }
        }
        .defaultSize(width: 800, height: 600)
        #endif
    }
}

public extension View {
    /// Opens the console without report attachments. Pass `reporting:` on iOS
    /// to add the Ladybug action and recent screen recording.
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
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    var reporting: DeveloperReporting? = nil
    @State private var window = DeveloperWindowState()
    #endif
    #if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        let hosted = content.background(DeveloperToolsAnchor(isEnabled: { options.isEnabled },
                                        onOpen: { options.requestConsole() }, onWindow: {
            window.value = $0
            synchronizeReporting()
        }).allowsHitTesting(false))
        #else
        let hosted = content
        #endif
        return hosted
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { options.refreshExpiration() }
            }
            .onOpenURL { url in
                if options.handle(url) {
                    #if os(visionOS)
                    if options.isEnabled { options.requestConsole() }
                    #endif
                }
            }
            #if os(iOS)
            .onChange(of: options.consoleRequested) { _, _ in synchronizeReporting() }
            .onChange(of: options.isEnabled, initial: true) { _, _ in synchronizeReporting() }
            .onChange(of: scenePhase) { _, phase in
                // ReplayKit's consent dialog briefly makes the scene inactive.
                if phase != .inactive { synchronizeReporting() }
            }
            .onDisappear { reporting?.coordinator.update(developerMode: options.isEnabled, isActive: false) }
            #elseif os(visionOS)
            .background {
                if options.isEnabled {
                    Button("Developer Console") { options.requestConsole() }
                        .keyboardShortcut(FoundationKeyboardShortcutCatalog.developerConsole.shortcut)
                        .hidden().accessibilityHidden(true)
                }
            }
            .task { options.launchSpatialConsole() }
            .onChange(of: options.consoleRequested, initial: true) { _, requested in
                if requested && options.isEnabled { openWindow(id: DeveloperConsoleScene.id) }
                else { dismissWindow(id: DeveloperConsoleScene.id) }
            }
            .onChange(of: options.isEnabled) { _, enabled in
                if !enabled { dismissWindow(id: DeveloperConsoleScene.id) }
            }
            #elseif os(macOS)
            .onChange(of: options.consoleRequested, initial: true) { _, requested in
                if requested && options.isEnabled { openWindow(id: DeveloperConsoleScene.id) }
                else { dismissWindow(id: DeveloperConsoleScene.id) }
            }
            .onChange(of: options.isEnabled) { _, enabled in
                if !enabled { dismissWindow(id: DeveloperConsoleScene.id) }
            }
            #endif
    }

    #if os(iOS)
    private func synchronizeReporting() {
        let active = window.value?.windowScene?.activationState == .foregroundActive
        reporting?.coordinator.update(developerMode: options.isEnabled, isActive: active)
        guard let reporting else {
            if !options.isEnabled || !options.consoleRequested { window.dismissConsole(); return }
            if active, let origin = window.value { window.presentConsole(from: origin, options: options) }
            return
        }
        if options.consoleRequested, options.isEnabled, active, let origin = window.value {
            reporting.present(from: origin)
            options.dismissConsole()
        }
    }
    #endif
}

#if os(iOS)
import UIKit
import MZAppFoundationReporting

@MainActor private final class DeveloperWindowState {
    weak var value: UIWindow?
    private var overlay: DeveloperOverlayWindow?
    private weak var host: UIViewController?

    func presentConsole(from origin: UIWindow, options: DeveloperOptions) {
        guard overlay == nil, let overlay = DeveloperOverlayWindow(from: origin) else { return }
        self.overlay = overlay
        let host = ConsoleHost(rootView: DeveloperConsole(options: options, onDismiss: { [weak self] in
            self?.dismissConsole()
            options.dismissConsole()
        }))
        host.didDismiss = { [weak self] in
            self?.dismissConsole()
            options.dismissConsole()
        }
        self.host = host
        overlay.presenter.present(host, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    func dismissConsole() {
        guard let overlay else { return }
        self.overlay = nil
        host = nil
        overlay.presenter.dismiss(animated: false)
        overlay.close()
    }
}

private final class ConsoleHost<Content: View>: UIHostingController<Content> {
    var didDismiss: (() -> Void)?
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController == nil || isBeingDismissed { didDismiss?() }
    }
}
#endif
