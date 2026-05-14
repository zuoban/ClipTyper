import SwiftUI
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set default shortcut on first launch (Cmd+Shift+V)
        if KeyboardShortcuts.getShortcut(for: .toggleTyping) == nil {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .toggleTyping)
        }

        registerShortcuts()

        // Check permissions on launch and prompt if needed
        if ProcessInfo.processInfo.environment["CLIPTYPER_SKIP_PERMISSION_PROMPT"] != "1" {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        if !AccessibilityHelper.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Accessibility Permission Required", comment: "")
                alert.informativeText = NSLocalizedString("ClipTyper needs accessibility permissions to simulate keystrokes. Please allow it in System Settings.", comment: "")
                alert.addButton(withTitle: NSLocalizedString("Authorize", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    AccessibilityHelper.requestPermission()
                    AccessibilityHelper.openSystemSettings()
                } else if response == .alertSecondButtonReturn {
                    NSApp.terminate(nil)
                }
            }
        }
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
