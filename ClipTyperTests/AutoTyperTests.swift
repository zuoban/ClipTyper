import XCTest
@testable import ClipTyper

@MainActor
final class AutoTyperTests: XCTestCase {
    func testStartTypingShowsFeedbackWhenClipboardIsEmpty() async {
        let typer = RecordingCharacterTyper()
        let autoTyper = makeAutoTyper(clipboardText: nil, characterTyper: typer)

        autoTyper.startTyping()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("No text in clipboard", comment: ""))
        let typedCharacters = await typer.typedCharacters
        XCTAssertTrue(typedCharacters.isEmpty)
    }

    func testStartTypingRequestsPermissionWhenAccessibilityIsMissing() {
        let permissions = StubPermissionHandler(isTrusted: false)
        let autoTyper = makeAutoTyper(clipboardText: "abc", permissionHandler: permissions)

        autoTyper.startTyping()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("Accessibility Permission Required", comment: ""))
        XCTAssertEqual(permissions.permissionRequestCount, 1)
    }

    func testStartTypingTypesClipboardCharacters() async {
        let typer = RecordingCharacterTyper()
        let autoTyper = makeAutoTyper(clipboardText: "ab", characterTyper: typer)

        autoTyper.startTyping()
        await autoTyper.waitForCurrentTypingTaskCompletion()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertNil(autoTyper.feedbackMessage)
        let typedCharacters = await typer.typedCharacters
        XCTAssertEqual(typedCharacters, ["a", "b"])
    }

    func testStartTypingTracksTypingProgress() async {
        let typer = RecordingCharacterTyper()
        let autoTyper = makeAutoTyper(clipboardText: "ab", characterTyper: typer)

        autoTyper.startTyping()

        XCTAssertEqual(autoTyper.typingProgress.current, 0)
        XCTAssertEqual(autoTyper.typingProgress.total, 2)

        await autoTyper.waitForCurrentTypingTaskCompletion()

        XCTAssertEqual(autoTyper.typingProgress.current, 2)
        XCTAssertEqual(autoTyper.typingProgress.total, 2)
    }

    func testStartTypingRejectsTextThatExceedsMaximumLength() async {
        let typer = RecordingCharacterTyper()
        let autoTyper = makeAutoTyper(
            clipboardText: "abcd",
            characterTyper: typer,
            maximumCharacterCount: 3
        )

        autoTyper.startTyping()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(
            autoTyper.feedbackMessage,
            String.localizedStringWithFormat(
                NSLocalizedString("Clipboard text is too long (%d character limit)", comment: ""),
                3
            )
        )
        let typedCharacters = await typer.typedCharacters
        XCTAssertTrue(typedCharacters.isEmpty)
    }

    func testStopTypingCancelsInProgressTyping() async {
        let typer = RecordingCharacterTyper(delayNanoseconds: 30_000_000)
        let autoTyper = makeAutoTyper(clipboardText: "abcd", characterTyper: typer)

        autoTyper.startTyping()
        await typer.waitUntilTypedCharacterCount(isAtLeast: 1)
        autoTyper.stopTyping()
        let typedCountAfterStop = await typer.typedCharacters.count
        await autoTyper.waitForCurrentTypingTaskCompletion()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("Typing stopped", comment: ""))
        let typedCountAfterWaiting = await typer.typedCharacters.count
        XCTAssertEqual(typedCountAfterWaiting, typedCountAfterStop)
    }

    func testStopTypingKeepsProgressAtStoppedCharacterCount() async {
        let typer = RecordingCharacterTyper(waitsForManualFinish: true)
        let autoTyper = makeAutoTyper(clipboardText: "abcd", characterTyper: typer)

        autoTyper.startTyping()
        await typer.waitUntilTypedCharacterCount(isAtLeast: 1)
        await typer.finishCurrentCharacterTyping()
        await typer.waitUntilTypedCharacterCount(isAtLeast: 2)
        autoTyper.stopTyping()

        await typer.finishCurrentCharacterTyping()
        await autoTyper.waitForCurrentTypingTaskCompletion()

        XCTAssertEqual(autoTyper.typingProgress.current, 1)
        XCTAssertEqual(autoTyper.typingProgress.total, 4)
    }

    func testDoubleToggleStopsInProgressTyping() async {
        let typer = RecordingCharacterTyper(delayNanoseconds: 50_000_000)
        let autoTyper = makeAutoTyper(clipboardText: "abcdef", characterTyper: typer)

        autoTyper.toggleTyping()
        try? await Task.sleep(nanoseconds: 10_000_000)
        autoTyper.toggleTyping()

        await autoTyper.waitForCurrentTypingTaskCompletion()
        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("Typing stopped", comment: ""))
    }

    func testStartTypingNoOpWhileAlreadyTyping() async {
        let typer = RecordingCharacterTyper(delayNanoseconds: 30_000_000)
        let autoTyper = makeAutoTyper(clipboardText: "abcdef", characterTyper: typer)

        autoTyper.startTyping()
        XCTAssertTrue(autoTyper.isTyping)

        autoTyper.startTyping()
        XCTAssertTrue(autoTyper.isTyping)

        autoTyper.stopTyping()
        await autoTyper.waitForCurrentTypingTaskCompletion()
    }

    func testFeedbackMessageAutoClears() async {
        let autoTyper = makeAutoTyper(clipboardText: nil, feedbackDurationNanoseconds: 100_000_000)

        autoTyper.startTyping()
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("No text in clipboard", comment: ""))

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(autoTyper.feedbackMessage)
    }

    func testWaitForCurrentTypingTaskCompletionWaitsForCancelledTypingTaskToFinish() async {
        let typer = RecordingCharacterTyper(waitsForManualFinish: true)
        let autoTyper = makeAutoTyper(clipboardText: "abcd", characterTyper: typer)
        let waitCompletion = WaitCompletionProbe()

        autoTyper.startTyping()
        await typer.waitUntilTypedCharacterCount(isAtLeast: 1)
        autoTyper.stopTyping()

        let isTypingCharacterAfterStop = await typer.isTypingCharacter
        XCTAssertTrue(isTypingCharacterAfterStop)

        let waitTask = Task { @MainActor in
            await autoTyper.waitForCurrentTypingTaskCompletion()
            await waitCompletion.markCompleted()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        let didCompleteBeforeCharacterTypingFinished = await waitCompletion.isCompleted
        XCTAssertFalse(didCompleteBeforeCharacterTypingFinished)

        await typer.finishCurrentCharacterTyping()
        await waitTask.value
        let isTypingCharacterAfterWaiting = await typer.isTypingCharacter
        XCTAssertFalse(isTypingCharacterAfterWaiting)
    }

    private func makeAutoTyper(
        clipboardText: String?,
        permissionHandler: StubPermissionHandler? = nil,
        characterTyper: RecordingCharacterTyper? = nil,
        maximumCharacterCount: Int = 5_000,
        feedbackDurationNanoseconds: UInt64 = 1_000_000_000
    ) -> AutoTyper {
        let permissionHandler = permissionHandler ?? StubPermissionHandler(isTrusted: true)
        let characterTyper = characterTyper ?? RecordingCharacterTyper()

        return AutoTyper(
            clipboardProvider: StubClipboardProvider(text: clipboardText),
            permissionHandler: permissionHandler,
            characterTyper: characterTyper,
            settingsProvider: {
                TypingConfiguration(totalDuration: 0.01, jitter: 0)
            },
            initialDelayNanoseconds: 0,
            maximumCharacterCount: maximumCharacterCount,
            feedbackDurationNanoseconds: feedbackDurationNanoseconds
        )
    }
}

private final class StubClipboardProvider: ClipboardTextProviding {
    private let text: String?

    init(text: String?) {
        self.text = text
    }

    func currentText() -> String? {
        text
    }
}

private final class StubPermissionHandler: AccessibilityPermissionHandling {
    let isTrusted: Bool
    private(set) var permissionRequestCount = 0

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func handlePermissionRequired() {
        permissionRequestCount += 1
    }
}

private actor RecordingCharacterTyper: CharacterTyping {
    private var storage: [Character] = []
    private var countWaiters: [(minimumCount: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private let delayNanoseconds: UInt64
    private let waitsForManualFinish: Bool
    private var manualFinishContinuation: CheckedContinuation<Void, Never>?

    var typedCharacters: [Character] {
        storage
    }

    var isTypingCharacter: Bool {
        activeTypingCount > 0
    }

    private var activeTypingCount = 0

    init(delayNanoseconds: UInt64 = 0, waitsForManualFinish: Bool = false) {
        self.delayNanoseconds = delayNanoseconds
        self.waitsForManualFinish = waitsForManualFinish
    }

    func typeCharacter(_ char: Character, targetPID: pid_t?) async -> Bool {
        activeTypingCount += 1
        defer { activeTypingCount -= 1 }

        storage.append(char)
        resumeSatisfiedCountWaiters()

        if waitsForManualFinish {
            await withCheckedContinuation { continuation in
                manualFinishContinuation = continuation
            }
        } else if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return true
    }

    func waitUntilTypedCharacterCount(isAtLeast minimumCount: Int) async {
        guard storage.count < minimumCount else { return }

        await withCheckedContinuation { continuation in
            countWaiters.append((minimumCount, continuation))
        }
    }

    func finishCurrentCharacterTyping() {
        manualFinishContinuation?.resume()
        manualFinishContinuation = nil
    }

    private func resumeSatisfiedCountWaiters() {
        var remainingWaiters: [(minimumCount: Int, continuation: CheckedContinuation<Void, Never>)] = []

        for waiter in countWaiters {
            if storage.count >= waiter.minimumCount {
                waiter.continuation.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }

        countWaiters = remainingWaiters
    }
}

private actor WaitCompletionProbe {
    private var completed = false

    var isCompleted: Bool {
        completed
    }

    func markCompleted() {
        completed = true
    }
}
