import Foundation
import Combine

nonisolated struct TypingProgress: Equatable {
    let current: Int
    let total: Int

    init(current: Int = 0, total: Int = 0) {
        self.current = max(0, current)
        self.total = max(0, total)
    }

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(min(current, total)) / Double(total)
    }
}

@MainActor
class AutoTyper: ObservableObject {
    static let shared = AutoTyper()
    
    @Published var isTyping: Bool = false
    @Published var feedbackMessage: String?
    @Published var typingProgress = TypingProgress()
    private var typingTask: Task<Void, Never>?
    private var typingTaskID: UUID?
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
        typingProgress = TypingProgress()

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
            showFeedback(
                String.localizedStringWithFormat(
                    NSLocalizedString("Clipboard text is too long (%d character limit)", comment: ""),
                    maximumCharacterCount
                )
            )
            return
        }

        isTyping = true
        feedbackMessage = NSLocalizedString("Typing...", comment: "")
        typingProgress = TypingProgress(current: 0, total: plan.characterCount)

        let runID = UUID()
        typingRunID = runID
        typingTaskID = runID

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
                await self.updateTypingProgress(runID: runID, current: index + 1, total: plan.characterCount)

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
        typingRunID = nil
        isTyping = false
        showFeedback(NSLocalizedString("Typing stopped", comment: ""))
    }

    func waitForCurrentTypingTaskCompletion() async {
        let task = typingTask
        let taskID = typingTaskID

        await task?.value

        if typingTaskID == taskID {
            typingTask = nil
            typingTaskID = nil
        }
    }

    private func updateTypingProgress(runID: UUID, current: Int, total: Int) {
        guard typingRunID == runID else { return }
        typingProgress = TypingProgress(current: current, total: total)
    }

    private func finishTyping(runID: UUID, feedback: String?) {
        guard typingRunID == runID else { return }

        isTyping = false
        typingTask = nil
        typingTaskID = nil
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
