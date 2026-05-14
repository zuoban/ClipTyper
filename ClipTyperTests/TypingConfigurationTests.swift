import XCTest
@testable import ClipTyper

final class TypingConfigurationTests: XCTestCase {
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
