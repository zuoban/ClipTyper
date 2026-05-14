import SwiftUI
import Combine

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("totalDurationMs") var totalDurationMs: Double = 1000
    @AppStorage("typingJitterMs") var typingJitterMs: Double = 20

    private init() {}
}

nonisolated enum AppConstants {
    static let totalDurationRange: ClosedRange<Double> = 100...3000
    static let totalDurationStep: Double = 100
    static let jitterRange: ClosedRange<Double> = 0...500
    static let jitterStep: Double = 10
}
