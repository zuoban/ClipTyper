import Cocoa
import Foundation

nonisolated struct TypingConfiguration {
    let totalDuration: TimeInterval
    let jitter: TimeInterval

    init(totalDuration: TimeInterval, jitter: TimeInterval) {
        self.totalDuration = totalDuration
        self.jitter = jitter
    }

    init(totalDurationMilliseconds: Double, typingJitterMilliseconds: Double) {
        let totalDurationMs = AppConstants.sanitizedTotalDurationMilliseconds(totalDurationMilliseconds)
        let jitterMs = AppConstants.sanitizedTypingJitterMilliseconds(typingJitterMilliseconds)

        self.totalDuration = totalDurationMs / 1_000
        self.jitter = jitterMs / 1_000
    }
}

@MainActor
protocol ClipboardTextProviding {
    func currentText() -> String?
}

@MainActor
protocol AccessibilityPermissionHandling {
    var isTrusted: Bool { get }
    func handlePermissionRequired()
}

@MainActor
protocol AccessibilityPermissionPrompting {
    func presentPermissionPrompt()
}

@MainActor
struct AccessibilityPermissionPromptCoordinator {
    typealias PermissionCheckScheduler = (@escaping @MainActor @Sendable () -> Void) -> Void

    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let permissionPrompter: any AccessibilityPermissionPrompting
    private let schedulePermissionCheck: PermissionCheckScheduler

    init(
        isAccessibilityTrusted: (@MainActor () -> Bool)? = nil,
        permissionPrompter: (any AccessibilityPermissionPrompting)? = nil,
        schedulePermissionCheck: PermissionCheckScheduler? = nil
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted ?? { AccessibilityHelper.isTrusted }
        self.permissionPrompter = permissionPrompter ?? SystemAccessibilityPermissionPrompter()
        self.schedulePermissionCheck = schedulePermissionCheck ?? { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { @MainActor in
                    action()
                }
            }
        }
    }

    func promptForPermissionsIfNeeded() {
        guard !isAccessibilityTrusted() else { return }

        schedulePermissionCheck { [isAccessibilityTrusted, permissionPrompter] in
            guard !isAccessibilityTrusted() else { return }
            permissionPrompter.presentPermissionPrompt()
        }
    }
}

nonisolated protocol CharacterTyping: Sendable {
    func typeCharacter(_ char: Character) async -> Bool
}

struct SystemClipboardProvider: ClipboardTextProviding {
    func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

struct SystemAccessibilityPermissionHandler: AccessibilityPermissionHandling {
    private let permissionPrompter: any AccessibilityPermissionPrompting

    @MainActor
    init(permissionPrompter: (any AccessibilityPermissionPrompting)? = nil) {
        self.permissionPrompter = permissionPrompter ?? SystemAccessibilityPermissionPrompter()
    }

    var isTrusted: Bool {
        AccessibilityHelper.isTrusted
    }

    func handlePermissionRequired() {
        permissionPrompter.presentPermissionPrompt()
    }
}

struct SystemAccessibilityPermissionPrompter: AccessibilityPermissionPrompting {
    func presentPermissionPrompt() {
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

nonisolated struct CGEventCharacterTyper: CharacterTyping {
    private let keyDownUpDelayNanoseconds: UInt64

    init(keyDownUpDelayNanoseconds: UInt64 = 1_000_000) {
        self.keyDownUpDelayNanoseconds = keyDownUpDelayNanoseconds
    }

    func typeCharacter(_ char: Character) async -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(String(char).utf16)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        guard keyDown?.post(tap: .cghidEventTap) != nil else { return false }

        try? await Task.sleep(nanoseconds: keyDownUpDelayNanoseconds)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        guard keyUp?.post(tap: .cghidEventTap) != nil else { return false }

        return true
    }
}
