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

    func testStartTypingRejectsTextThatExceedsMaximumLength() async {
        let typer = RecordingCharacterTyper()
        let autoTyper = makeAutoTyper(
            clipboardText: "abcd",
            characterTyper: typer,
            maximumCharacterCount: 3
        )

        autoTyper.startTyping()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("Clipboard text is too long", comment: ""))
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

    private func makeAutoTyper(
        clipboardText: String?,
        permissionHandler: StubPermissionHandler? = nil,
        characterTyper: RecordingCharacterTyper? = nil,
        maximumCharacterCount: Int = 5_000
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
            feedbackDurationNanoseconds: 1_000_000_000
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

    var typedCharacters: [Character] {
        storage
    }

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func typeCharacter(_ char: Character) async {
        storage.append(char)
        resumeSatisfiedCountWaiters()

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    func waitUntilTypedCharacterCount(isAtLeast minimumCount: Int) async {
        guard storage.count < minimumCount else { return }

        await withCheckedContinuation { continuation in
            countWaiters.append((minimumCount, continuation))
        }
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
