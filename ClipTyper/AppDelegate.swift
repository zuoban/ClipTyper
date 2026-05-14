import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionPromptCoordinator = AccessibilityPermissionPromptCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set default shortcut on first launch (Cmd+Shift+V)
        if KeyboardShortcuts.getShortcut(for: .toggleTyping) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .toggleTyping)
        }

        registerShortcuts()

        // Check permissions on launch and prompt if needed
        if Self.shouldPromptForPermissions(environment: ProcessInfo.processInfo.environment) {
            permissionPromptCoordinator.promptForPermissionsIfNeeded()
        }
    }

    nonisolated static func shouldPromptForPermissions(environment: [String: String]) -> Bool {
        guard environment["CLIPTYPER_SKIP_PERMISSION_PROMPT"] != "1" else { return false }
        guard environment["XCTestConfigurationFilePath"] == nil else { return false }
        return true
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleTyping) {
            Task { @MainActor in
                AutoTyper.shared.toggleTyping()
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleTyping = Self("toggleTyping")
}
