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
        let totalDurationMs = Self.sanitized(
            totalDurationMilliseconds,
            fallback: 1_000,
            range: AppConstants.totalDurationRange
        )
        let jitterMs = Self.sanitized(
            typingJitterMilliseconds,
            fallback: 20,
            range: AppConstants.jitterRange
        )

        self.totalDuration = totalDurationMs / 1_000
        self.jitter = jitterMs / 1_000
    }

    private static func sanitized(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        return min(max(finiteValue, range.lowerBound), range.upperBound)
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

nonisolated protocol CharacterTyping: Sendable {
    func typeCharacter(_ char: Character) async
}

struct SystemClipboardProvider: ClipboardTextProviding {
    func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

struct SystemAccessibilityPermissionHandler: AccessibilityPermissionHandling {
    var isTrusted: Bool {
        AccessibilityHelper.isTrusted
    }

    func handlePermissionRequired() {
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

    func typeCharacter(_ char: Character) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(String(char).utf16)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyDown?.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: keyDownUpDelayNanoseconds)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyUp?.post(tap: .cghidEventTap)
    }
}
