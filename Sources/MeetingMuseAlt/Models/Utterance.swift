import Foundation

public struct Utterance: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let speaker: Speaker
    public let text: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        startSeconds: Double,
        endSeconds: Double,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.confidence = confidence
    }

    public var timestampLabel: String {
        let total = Int(startSeconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    public var duration: Double { max(0, endSeconds - startSeconds) }
}
