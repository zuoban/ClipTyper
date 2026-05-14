import SwiftUI
import Combine

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @AppStorage("totalDurationMs") var totalDurationMs: Double = 1000 // Default 1 second
    @AppStorage("typingJitterMs") var typingJitterMs: Double = 20 // Default 20ms jitter
    
    private init() {}
}
