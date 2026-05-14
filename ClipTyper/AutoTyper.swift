import Foundation
import Cocoa
import Combine

@MainActor
class AutoTyper: ObservableObject {
    static let shared = AutoTyper()
    
    @Published var isTyping: Bool = false
    @Published var feedbackMessage: String?
    private var typingTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var typingRunID: UUID?
    
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
        feedbackClearTask?.cancel()
        feedbackMessage = nil

        // Check accessibility permission
        guard AccessibilityHelper.isTrusted else {
            showPermissionAlert()
            return
        }

        // Snapshot clipboard content
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            showFeedback(NSLocalizedString("No text in clipboard", comment: ""))
            return
        }

        isTyping = true
        feedbackMessage = NSLocalizedString("Typing...", comment: "")

        // Capture settings on MainActor
        let totalDuration = AppSettings.shared.totalDurationMs / 1000.0 // seconds
        let jitter = AppSettings.shared.typingJitterMs / 1000.0 // seconds
        let plan = TypingPlan(text: text, totalDuration: totalDuration, jitter: jitter)
        let runID = UUID()
        typingRunID = runID

        typingTask = Task.detached(priority: .userInitiated) { [plan, runID] in
            // Initial delay to let the OS and target app stabilize after hotkey press
            try? await Task.sleep(nanoseconds: UInt64(Self.initialDelayMs * 1_000_000))
            if Task.isCancelled {
                await self.finishTyping(runID: runID, feedback: nil)
                return
            }

            let startTime = ContinuousClock.now

            for (index, char) in plan.characters.enumerated() {
                if Task.isCancelled { break }

                await self.typeCharacter(char)

                // Deadline-based timing to prevent drift
                let targetElapsed = plan.targetElapsedTime(afterCharacterAt: index)
                let randomJitter = Double.random(in: -plan.clampedJitter/2...plan.clampedJitter/2)
                let duration = startTime.duration(to: ContinuousClock.now)
                let elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                let remaining = targetElapsed + randomJitter - elapsed

                if remaining > 0.001 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }

            let feedback = Task.isCancelled ? NSLocalizedString("Typing stopped", comment: "") : nil
            await self.finishTyping(runID: runID, feedback: feedback)
        }
    }

    func stopTyping() {
        typingTask?.cancel()
        typingTask = nil
        typingRunID = nil
        isTyping = false
        showFeedback(NSLocalizedString("Typing stopped", comment: ""))
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
            AccessibilityHelper.openSystemSettings()
        } else if response == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func finishTyping(runID: UUID, feedback: String?) {
        guard typingRunID == runID else { return }

        isTyping = false
        typingTask = nil
        typingRunID = nil

        if let feedback {
            showFeedback(feedback)
        } else {
            feedbackMessage = nil
        }
    }

    private func showFeedback(_ message: String) {
        feedbackClearTask?.cancel()
        feedbackMessage = message

        feedbackClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self.feedbackMessage = nil
            self.feedbackClearTask = nil
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
