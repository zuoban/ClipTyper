import Foundation
import Combine

@MainActor
class AutoTyper: ObservableObject {
    static let shared = AutoTyper()
    
    @Published var isTyping: Bool = false
    @Published var feedbackMessage: String?
    private var typingTask: Task<Void, Never>?
    private var feedbackClearTask: Task<Void, Never>?
    private var typingRunID: UUID?
    private let clipboardProvider: ClipboardTextProviding
    private let permissionHandler: AccessibilityPermissionHandling
    private let characterTyper: CharacterTyping
    private let settingsProvider: () -> TypingConfiguration
    private let initialDelayNanoseconds: UInt64
    private let maximumCharacterCount: Int
    private let feedbackDurationNanoseconds: UInt64

    convenience init() {
        self.init(
            clipboardProvider: SystemClipboardProvider(),
            permissionHandler: SystemAccessibilityPermissionHandler(),
            characterTyper: CGEventCharacterTyper(),
            settingsProvider: {
                TypingConfiguration(
                    totalDurationMilliseconds: AppSettings.shared.totalDurationMs,
                    typingJitterMilliseconds: AppSettings.shared.typingJitterMs
                )
            }
        )
    }
    
    init(
        clipboardProvider: ClipboardTextProviding,
        permissionHandler: AccessibilityPermissionHandling,
        characterTyper: CharacterTyping,
        settingsProvider: @escaping () -> TypingConfiguration,
        initialDelayNanoseconds: UInt64 = 200_000_000,
        maximumCharacterCount: Int = 5_000,
        feedbackDurationNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.clipboardProvider = clipboardProvider
        self.permissionHandler = permissionHandler
        self.characterTyper = characterTyper
        self.settingsProvider = settingsProvider
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.maximumCharacterCount = maximumCharacterCount
        self.feedbackDurationNanoseconds = feedbackDurationNanoseconds
    }
    
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
        guard permissionHandler.isTrusted else {
            permissionHandler.handlePermissionRequired()
            return
        }

        // Snapshot clipboard content
        guard let text = clipboardProvider.currentText(), !text.isEmpty else {
            showFeedback(NSLocalizedString("No text in clipboard", comment: ""))
            return
        }

        // Capture settings on MainActor
        let configuration = settingsProvider()
        let plan = TypingPlan(text: text, totalDuration: configuration.totalDuration, jitter: configuration.jitter)
        guard plan.characterCount <= maximumCharacterCount else {
            showFeedback(NSLocalizedString("Clipboard text is too long", comment: ""))
            return
        }

        isTyping = true
        feedbackMessage = NSLocalizedString("Typing...", comment: "")

        let runID = UUID()
        typingRunID = runID

        typingTask = Task.detached(priority: .userInitiated) { [plan, runID, initialDelayNanoseconds, characterTyper] in
            // Initial delay to let the OS and target app stabilize after hotkey press
            try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            if Task.isCancelled {
                await self.finishTyping(runID: runID, feedback: nil)
                return
            }

            let startTime = ContinuousClock.now

            for (index, char) in plan.characters.enumerated() {
                if Task.isCancelled { break }

                await characterTyper.typeCharacter(char)

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
            try? await Task.sleep(nanoseconds: feedbackDurationNanoseconds)
            guard !Task.isCancelled else { return }
            self.feedbackMessage = nil
            self.feedbackClearTask = nil
        }
    }
}
