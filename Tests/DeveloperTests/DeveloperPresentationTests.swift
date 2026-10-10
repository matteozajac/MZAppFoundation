import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI
import Testing
import UIKit

@Suite(.serialized) @MainActor
struct DeveloperPresentationTests {
    @Test func commandDWithoutTextInputOpensConsole() async throws {
        try await withFixture { options, window, controller in
            let command = try #require(controller.keyCommands?.first { $0.input == "d" })
            let action = try #require(command.action)
            #expect(UIApplication.shared.sendAction(action, to: nil, from: command, for: nil))
            try await wait { !window.isKeyWindow }
            options.dismissConsole()
            try await wait { window.isKeyWindow }
        }
    }
    @Test func commandDAboveSheetPreservesTextAndRestoresKeyWindow() async throws {
        try await withFixture { options, window, controller in
            let sheet = UIViewController()
            sheet.view.backgroundColor = .systemBackground
            let field = UITextField(frame: CGRect(x: 30, y: 100, width: 240, height: 44))
            field.text = "Unfinished app work"
            sheet.view.addSubview(field)
            controller.children[0].present(sheet, animated: false)
            try await wait { sheet.view.window != nil }
            #expect(field.becomeFirstResponder())
            #expect(field.isFirstResponder)
            let matchingCommand = controller.keyCommands?.first { $0.input == "d" && $0.modifierFlags == UIKeyModifierFlags.command }
            let command = try #require(matchingCommand)
            let action = try #require(command.action)
            #expect(UIApplication.shared.sendAction(action, to: nil, from: command, for: nil))
            try await wait { window.windowScene?.windows.contains { $0 !== window && $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil } == true }
            #expect(controller.children[0].presentedViewController === sheet)
            #expect(field.text == "Unfinished app work")
            options.dismissConsole()
            try await wait { window.isKeyWindow }
            #expect(controller.children[0].presentedViewController === sheet)
            #expect(field.text == "Unfinished app work")
            #expect(field.becomeFirstResponder())
            field.text?.append(" preserved")
            #expect(field.text == "Unfinished app work preserved")
            options.setEnabled(false)
            #expect(controller.keyCommands?.contains { $0.input == "d" } != true)
            #expect(!UIApplication.shared.sendAction(action, to: nil, from: command, for: nil))
        }
    }

    @Test func forwardedShakeAboveAlertLeavesAlertPresented() async throws {
        try await withFixture { options, window, controller in
            let alert = UIAlertController(title: "Original app alert", message: "Pending choice", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
            controller.children[0].present(alert, animated: false)
            try await wait { alert.view.window != nil }
            // Exercises public UIKit motion forwarding from the presented controller.
            // Physical accelerometer delivery remains a device acceptance check.
            alert.motionEnded(.motionShake, with: nil)
            try await wait { window.windowScene?.windows.contains { $0 !== window && $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil } == true }
            #expect(controller.children[0].presentedViewController === alert)
            options.setEnabled(false)
            try await wait { window.isKeyWindow }
            #expect(controller.children[0].presentedViewController === alert)
            #expect(alert.title == "Original app alert")
            #expect(!options.consoleRequested)
        }
    }

    private func withFixture(_ operation: (DeveloperOptions, UIWindow, UIViewController) async throws -> Void) async throws {
        let suite = "DeveloperPresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = DeveloperOptions(configuration: .init(bundleIdentifier: "com.example.fixture", urlScheme: "fixture", environment: .local), defaults: defaults)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: NavigationStack { Text("Host content") }.appDeveloperTools(options))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { options.dismissConsole(); window.isHidden = true; previous?.makeKey() }
        try await wait { findTools(in: window.rootViewController ?? host) != nil }
        let controller = try #require(findTools(in: window.rootViewController ?? host))
        // Installing the root container precedes UIKit's appearance callback.
        // Let the production responder become active before sending hardware keys.
        try await wait {
            window.isKeyWindow
                && (controller.isFirstResponder || controller.children.contains { $0.isFirstResponder })
        }
        try await operation(options, window, controller)
    }

    private func findTools(in controller: UIViewController) -> UIViewController? {
        if String(describing: type(of: controller)).contains("DeveloperResponderController"), controller.view.window != nil { return controller }
        return controller.children.lazy.compactMap { findTools(in: $0) }.first
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(30)) }
        try #require(predicate())
    }

}
