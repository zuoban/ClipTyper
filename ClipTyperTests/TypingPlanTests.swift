import XCTest
@testable import ClipTyper

final class TypingPlanTests: XCTestCase {
    func testCachesCharactersAndCountsExtendedGraphemeClusters() {
        let plan = TypingPlan(text: "a👨‍👩‍👧‍👦中", totalDuration: 1.2, jitter: 0.6)

        XCTAssertEqual(plan.characterCount, 3)
        XCTAssertEqual(plan.characters.map(String.init), ["a", "👨‍👩‍👧‍👦", "中"])
    }

    func testTargetElapsedTimeDistributesTotalDurationAcrossCharacters() {
        let plan = TypingPlan(text: "abcd", totalDuration: 2.0, jitter: 0.2)

        XCTAssertEqual(plan.targetElapsedTime(afterCharacterAt: 0), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(plan.targetElapsedTime(afterCharacterAt: 1), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(plan.targetElapsedTime(afterCharacterAt: 3), 2.0, accuracy: 0.000_001)
    }

    func testClampedJitterDoesNotExceedAverageCharacterInterval() {
        let plan = TypingPlan(text: "abcd", totalDuration: 2.0, jitter: 3.0)

        XCTAssertEqual(plan.clampedJitter, 0.5, accuracy: 0.000_001)
    }

    func testInfiniteConfigurationFallsBackToZeroTiming() {
        let plan = TypingPlan(text: "abcd", totalDuration: .infinity, jitter: .infinity)

        XCTAssertEqual(plan.totalDuration, 0)
        XCTAssertEqual(plan.clampedJitter, 0)
        XCTAssertEqual(plan.targetElapsedTime(afterCharacterAt: 2), 0)
    }
}
