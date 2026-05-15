import XCTest
@testable import ClipTyper

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testPermissionHandlerIsTrustedDelegatesToInjectedClosure() {
        let untrusted = SystemAccessibilityPermissionHandler(isAccessibilityTrusted: { false })
        XCTAssertFalse(untrusted.isTrusted)

        let trusted = SystemAccessibilityPermissionHandler(isAccessibilityTrusted: { true })
        XCTAssertTrue(trusted.isTrusted)
    }

    @MainActor
    func testPermissionHandlerHandlePermissionRequiredCallsPrompter() {
        let prompter = SpyPermissionPrompter()
        let handler = SystemAccessibilityPermissionHandler(
            isAccessibilityTrusted: { false },
            permissionPrompter: prompter
        )

        handler.handlePermissionRequired()

        XCTAssertEqual(prompter.presentCount, 1)
    }
}

@MainActor
private final class SpyPermissionPrompter: AccessibilityPermissionPrompting {
    private(set) var presentCount = 0

    func presentPermissionPrompt() {
        presentCount += 1
    }
}
