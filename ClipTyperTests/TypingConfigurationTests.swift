import XCTest
@testable import ClipTyper

final class TypingConfigurationTests: XCTestCase {
    func testAppConstantsSanitizeTypingSettingsMilliseconds() {
        XCTAssertEqual(AppConstants.sanitizedTotalDurationMilliseconds(.infinity), 1_000)
        XCTAssertEqual(AppConstants.sanitizedTotalDurationMilliseconds(20_000), 3_000)
        XCTAssertEqual(AppConstants.sanitizedTypingJitterMilliseconds(.nan), 20)
        XCTAssertEqual(AppConstants.sanitizedTypingJitterMilliseconds(-10), 0)
    }

    func testSettingsMillisecondsAreClampedToAllowedRanges() {
        let configuration = TypingConfiguration(
            totalDurationMilliseconds: 20_000,
            typingJitterMilliseconds: -10
        )

        XCTAssertEqual(configuration.totalDuration, 3.0)
        XCTAssertEqual(configuration.jitter, 0.0)
    }

    func testNonFiniteSettingsMillisecondsUseDefaultValues() {
        let configuration = TypingConfiguration(
            totalDurationMilliseconds: .infinity,
            typingJitterMilliseconds: .nan
        )

        XCTAssertEqual(configuration.totalDuration, 1.0)
        XCTAssertEqual(configuration.jitter, 0.02)
    }
}
