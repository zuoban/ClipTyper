import XCTest
@testable import ClipTyper

@MainActor
final class AutoTyperTests: XCTestCase {
    func testStartTypingShowsFeedbackWhenClipboardIsEmpty() {
        let typer = RecordingCharacterTyper()
        let autoTyper = makeAutoTyper(clipboardText: nil, characterTyper: typer)

        autoTyper.startTyping()

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("No text in clipboard", comment: ""))
        XCTAssertTrue(typer.typedCharacters.isEmpty)
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
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertNil(autoTyper.feedbackMessage)
        XCTAssertEqual(typer.typedCharacters, ["a", "b"])
    }

    func testStopTypingCancelsInProgressTyping() async {
        let typer = RecordingCharacterTyper(delayNanoseconds: 30_000_000)
        let autoTyper = makeAutoTyper(clipboardText: "abcd", characterTyper: typer)

        autoTyper.startTyping()
        try? await Task.sleep(nanoseconds: 5_000_000)
        autoTyper.stopTyping()
        let typedCountAfterStop = typer.typedCharacters.count
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(autoTyper.isTyping)
        XCTAssertEqual(autoTyper.feedbackMessage, NSLocalizedString("Typing stopped", comment: ""))
        XCTAssertEqual(typer.typedCharacters.count, typedCountAfterStop)
    }

    private func makeAutoTyper(
        clipboardText: String?,
        permissionHandler: StubPermissionHandler? = nil,
        characterTyper: RecordingCharacterTyper? = nil
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

private final class RecordingCharacterTyper: CharacterTyping, @unchecked Sendable {
    private var storage: [Character] = []
    private let lock = NSLock()
    private let delayNanoseconds: UInt64

    var typedCharacters: [Character] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func typeCharacter(_ char: Character) async {
        lock.lock()
        storage.append(char)
        lock.unlock()

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }
}
