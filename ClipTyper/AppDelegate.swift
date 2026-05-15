import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionHandler = SystemAccessibilityPermissionHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set default shortcut on first launch (Cmd+Shift+V)
        if KeyboardShortcuts.getShortcut(for: .toggleTyping) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .toggleTyping)
        }

        registerShortcuts()

        // Check permissions on launch and prompt if needed (with 1s delay)
        if Self.shouldPromptForPermissions(environment: ProcessInfo.processInfo.environment) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [permissionHandler] in
                guard !permissionHandler.isTrusted else { return }
                permissionHandler.handlePermissionRequired()
            }
        }

        setupAppMenu()
    }

    private func setupAppMenu() {
        guard let mainMenu = NSApp.mainMenu,
              let appMenu = mainMenu.items.first?.submenu else { return }

        let aboutTitle = NSLocalizedString("About ClipTyper", comment: "")
        let aboutItem = NSMenuItem(
            title: aboutTitle,
            action: #selector(AppDelegate.showAboutPanel),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.insertItem(aboutItem, at: 0)

        let updateItem = NSMenuItem(
            title: NSLocalizedString("Check for Updates...", comment: ""),
            action: #selector(AppDelegate.checkForUpdatesAction),
            keyEquivalent: ""
        )
        updateItem.target = self
        appMenu.insertItem(updateItem, at: 1)

        appMenu.insertItem(.separator(), at: 2)
    }

    @objc private func checkForUpdatesAction() {
        Task {
            await UpdateChecker.shared.checkForUpdates()
        }
    }

    @objc private func showAboutPanel() {
        let credits = NSAttributedString(
            string: "https://github.com/zuoban/ClipTyper",
            attributes: [.link: URL(string: "https://github.com/zuoban/ClipTyper")!]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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
