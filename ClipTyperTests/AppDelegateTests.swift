import XCTest
@testable import ClipTyper

final class AppDelegateTests: XCTestCase {
    func testPermissionPromptIsSkippedWhenRunningUnitTests() {
        let environment = [
            "XCTestConfigurationFilePath": "/tmp/ClipTyperTests.xctestconfiguration"
        ]

        XCTAssertFalse(AppDelegate.shouldPromptForPermissions(environment: environment))
    }

    func testPermissionPromptCanBeExplicitlySkipped() {
        let environment = [
            "CLIPTYPER_SKIP_PERMISSION_PROMPT": "1"
        ]

        XCTAssertFalse(AppDelegate.shouldPromptForPermissions(environment: environment))
    }

    func testPermissionPromptIsAllowedOutsideTests() {
        XCTAssertTrue(AppDelegate.shouldPromptForPermissions(environment: [:]))
    }

    @MainActor
    func testPromptForPermissionsUsesInjectedPrompterWhenAccessibilityIsMissing() {
        let prompter = SpyPermissionPrompter()
        let coordinator = AccessibilityPermissionPromptCoordinator(
            isAccessibilityTrusted: { false },
            permissionPrompter: prompter,
            schedulePermissionCheck: { action in action() }
        )

        coordinator.promptForPermissionsIfNeeded()

        XCTAssertEqual(prompter.presentCount, 1)
    }

    @MainActor
    func testPromptForPermissionsDoesNotPromptWhenAccessibilityIsTrusted() {
        let prompter = SpyPermissionPrompter()
        let coordinator = AccessibilityPermissionPromptCoordinator(
            isAccessibilityTrusted: { true },
            permissionPrompter: prompter,
            schedulePermissionCheck: { action in action() }
        )

        coordinator.promptForPermissionsIfNeeded()

        XCTAssertEqual(prompter.presentCount, 0)
    }
}

@MainActor
private final class SpyPermissionPrompter: AccessibilityPermissionPrompting {
    private(set) var presentCount = 0

    func presentPermissionPrompt() {
        presentCount += 1
    }
}
