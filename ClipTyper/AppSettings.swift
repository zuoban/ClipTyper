import SwiftUI
import Combine

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("totalDurationMs") private var storedTotalDurationMs: Double = 1000
    @AppStorage("typingJitterMs") private var storedTypingJitterMs: Double = 20

    var totalDurationMs: Double {
        get {
            AppConstants.sanitizedTotalDurationMilliseconds(storedTotalDurationMs)
        }
        set {
            storedTotalDurationMs = AppConstants.sanitizedTotalDurationMilliseconds(newValue)
        }
    }

    var typingJitterMs: Double {
        get {
            AppConstants.sanitizedTypingJitterMilliseconds(storedTypingJitterMs)
        }
        set {
            storedTypingJitterMs = AppConstants.sanitizedTypingJitterMilliseconds(newValue)
        }
    }

    private init() {}
}

nonisolated enum AppConstants {
    static let totalDurationRange: ClosedRange<Double> = 100...3000
    static let totalDurationStep: Double = 100
    static let jitterRange: ClosedRange<Double> = 0...500
    static let jitterStep: Double = 10

    static func sanitizedTotalDurationMilliseconds(_ value: Double) -> Double {
        sanitized(value, fallback: 1_000, range: totalDurationRange)
    }

    static func sanitizedTypingJitterMilliseconds(_ value: Double) -> Double {
        sanitized(value, fallback: 20, range: jitterRange)
    }

    private static func sanitized(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        return min(max(finiteValue, range.lowerBound), range.upperBound)
    }
}
