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
}
