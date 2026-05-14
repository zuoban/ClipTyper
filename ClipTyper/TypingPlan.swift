import Foundation

nonisolated struct TypingPlan {
    let characters: [Character]
    let totalDuration: TimeInterval
    let clampedJitter: TimeInterval

    var characterCount: Int {
        characters.count
    }

    init(text: String, totalDuration: TimeInterval, jitter: TimeInterval) {
        let characters = Array(text)
        let sanitizedTotalDuration = totalDuration.isFinite ? max(0, totalDuration) : 0
        let sanitizedJitter = jitter.isFinite ? max(0, jitter) : 0

        self.characters = characters
        self.totalDuration = sanitizedTotalDuration

        guard !characters.isEmpty else {
            self.clampedJitter = 0
            return
        }

        let averageInterval = self.totalDuration / Double(characters.count)
        self.clampedJitter = min(sanitizedJitter, averageInterval)
    }

    func targetElapsedTime(afterCharacterAt index: Int) -> TimeInterval {
        guard !characters.isEmpty else { return 0 }

        let completedCharacters = min(max(index + 1, 0), characters.count)
        let progress = Double(completedCharacters) / Double(characters.count)
        return totalDuration * progress
    }
}
