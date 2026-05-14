import Foundation
import Cocoa
import Carbon
import Combine

@MainActor
class AutoTyper: ObservableObject {
    static let shared = AutoTyper()
    
    @Published var isTyping: Bool = false
    @Published var feedbackMessage: String?
    private var typingTask: Task<Void, Never>?
    
    private init() {}
    
    func toggleTyping() {
        if isTyping {
            stopTyping()
        } else {
            startTyping()
        }
    }
    
    func startTyping() {
        guard !isTyping else { return }

        // Check accessibility permission
        guard AccessibilityHelper.isTrusted else {
            showPermissionAlert()
            return
        }

        // Snapshot clipboard content
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            Task { @MainActor in
                self.feedbackMessage = NSLocalizedString("No text in clipboard", comment: "")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.feedbackMessage = nil
            }
            return
        }

        isTyping = true

        // Capture settings on MainActor
        let totalDuration = AppSettings.shared.totalDurationMs / 1000.0 // seconds
        let jitter = AppSettings.shared.typingJitterMs / 1000.0 // seconds

        typingTask = Task.detached(priority: .userInitiated) {
            // Initial delay to let the OS and target app stabilize after hotkey press
            try? await Task.sleep(nanoseconds: UInt64(Self.initialDelayMs * 1_000_000))

            let startTime = ContinuousClock.now

            for (index, char) in text.enumerated() {
                if Task.isCancelled { break }

                await self.typeCharacter(char)

                // Deadline-based timing to prevent drift
                let progress = Double(index + 1) / Double(text.count)
                let targetElapsed = totalDuration * progress
                let randomJitter = Double.random(in: -jitter/2...jitter/2)
                let duration = startTime.duration(to: ContinuousClock.now)
                let elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                let remaining = targetElapsed + randomJitter - elapsed

                if remaining > 0.001 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }

            await MainActor.run {
                self.isTyping = false
                self.typingTask = nil
            }
        }
    }

    func stopTyping() {
        typingTask?.cancel()
        isTyping = false
        // typingTask is nulled by the task itself
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Accessibility Permission Required", comment: "")
        alert.informativeText = NSLocalizedString("ClipTyper needs accessibility permissions to simulate keystrokes. Please allow it in System Settings.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Authorize", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            AccessibilityHelper.requestPermission()
        } else if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
    
    nonisolated private func typeCharacter(_ char: Character) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(String(char).utf16)

        // Key Down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyDown?.post(tap: .cghidEventTap)

        // Non-blocking sleep between down and up
        try? await Task.sleep(nanoseconds: Self.keyDownUpDelayNanoseconds)

        // Key Up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyUp?.post(tap: .cghidEventTap)
    }

    // Timing constants
    private static let initialDelayMs: Double = 200
    private static let keyDownUpDelayNanoseconds: UInt64 = 1_000_000 // 1ms
}
