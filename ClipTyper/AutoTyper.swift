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

        guard let plan = prepareTypingPlan() else { return }

        isTyping = true
        feedbackMessage = NSLocalizedString("Typing...", comment: "")
        typingProgress = TypingProgress(current: 0, total: plan.characterCount)

        let runID = UUID()
        typingRunID = runID
        typingTask = makeTypingTask(plan: plan, runID: runID)
    }

    private func prepareTypingPlan() -> TypingPlan? {
        guard permissionHandler.isTrusted else {
            showFeedback(NSLocalizedString("Accessibility Permission Required", comment: ""))
            permissionHandler.handlePermissionRequired()
            return nil
        }

        guard let text = clipboardProvider.currentText(), !text.isEmpty else {
            showFeedback(NSLocalizedString("No text in clipboard", comment: ""))
            return nil
        }

        let configuration = settingsProvider()
        let plan = TypingPlan(text: text, totalDuration: configuration.totalDuration, jitter: configuration.jitter)
        guard plan.characterCount <= maximumCharacterCount else {
            showFeedback(
                String.localizedStringWithFormat(
                    NSLocalizedString("Clipboard text is too long (%d character limit)", comment: ""),
                    maximumCharacterCount
                )
            )
            return nil
        }

        return plan
    }

    private func makeTypingTask(plan: TypingPlan, runID: UUID) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { [plan, runID, initialDelayNanoseconds, characterTyper] in
            try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
            if Task.isCancelled {
                await self.finishTyping(runID: runID, feedback: nil)
                return
            }

            let startTime = ContinuousClock.now

            var consecutiveFailures = 0
            for (index, char) in plan.characters.enumerated() {
                if Task.isCancelled { break }

                let success = await characterTyper.typeCharacter(char)
                if !success {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 {
                        await self.finishTyping(runID: runID, feedback: NSLocalizedString("Keystroke injection failed", comment: ""))
                        return
                    }
                    continue
                }
                consecutiveFailures = 0

                await self.updateTypingProgress(runID: runID, current: index + 1, total: plan.characterCount)

                let targetElapsed = plan.targetElapsedTime(afterCharacterAt: index)
                let randomJitter = Double.random(in: -plan.clampedJitter/2...plan.clampedJitter/2)
                let duration = startTime.duration(to: ContinuousClock.now)
                let elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                let drift = elapsed - targetElapsed
                let remaining = targetElapsed + randomJitter - elapsed - drift * 0.3

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
        let runID = typingRunID

        await task?.value

        if typingRunID == runID {
            typingTask = nil
            typingRunID = nil
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
