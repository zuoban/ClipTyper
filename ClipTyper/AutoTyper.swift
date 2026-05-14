import Foundation
import Cocoa
import Carbon
import Combine

@MainActor
class AutoTyper: ObservableObject {
    static let shared = AutoTyper()
    
    @Published var isTyping: Bool = false
    private var typingTask: Task<Void, Never>?
    
    private init() {}
    
    func toggleTyping() {
        if isTyping {
            stopTyping()
        } else {
            startTyping()
        }
    }
    
    func startTyping() {
        guard !isTyping else { return }
        
        // Snapshot clipboard content
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        
        isTyping = true
        
        // Capture settings on MainActor
        let totalDuration = AppSettings.shared.totalDurationMs / 1000.0 // seconds
        let jitter = AppSettings.shared.typingJitterMs / 1000.0 // seconds
        let charCount = Double(text.count)
        let baseInterval = charCount > 1 ? totalDuration / (charCount - 1) : 0
        
        typingTask = Task.detached(priority: .userInitiated) {
            // Initial delay to let the OS and target app stabilize after hotkey press
            try? await Task.sleep(nanoseconds: 200 * 1_000_000) // 200ms
            
            for char in text {
                if Task.isCancelled { break }
                
                self.typeCharacter(char)
                
                // Calculate delay with jitter
                let randomJitter = Double.random(in: -jitter/2...jitter/2)
                let totalDelay = max(0.001, baseInterval + randomJitter)
                
                try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
            }
            
            await MainActor.run {
                self.isTyping = false
                self.typingTask = nil
            }
        }
    }
    
    func stopTyping() {
        typingTask?.cancel()
        isTyping = false
        typingTask = nil
    }
    
    nonisolated private func typeCharacter(_ char: Character) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(String(char).utf16)
        
        // Key Down
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyDown?.post(tap: .cghidEventTap)
        
        // Tiny sleep between down and up (optional but helps some apps)
        Thread.sleep(forTimeInterval: 0.001) 
        
        // Key Up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyUp?.post(tap: .cghidEventTap)
    }
}
