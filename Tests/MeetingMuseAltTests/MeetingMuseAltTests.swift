import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func utteranceTimestampFormatting() {
    let utt = Utterance(
        speaker: Speaker(id: "A"),
        text: "Hello",
        startSeconds: 65,
        endSeconds: 70
    )
    #expect(utt.timestampLabel == "01:05")
    #expect(utt.duration == 5)
}

@Test func speakerDefaultLabel() {
    let s = Speaker(id: "B")
    #expect(s.label == "B")
}

@Test func detectorWhitelistContainsZoomAndTeams() {
    #expect(MeetingAppDetector.bundleWhitelist["us.zoom.xos"] != nil)
    #expect(MeetingAppDetector.bundleWhitelist["com.microsoft.teams2"] != nil)
}

@Test func whisperEngineStubReturnsUtterancesForMissingFile() async throws {
    let engine = WhisperEngine(mode: .stub)
    let url = URL(fileURLWithPath: "/tmp/nonexistent-meeting-muse-test.caf")
    let result = try await engine.transcribe(audioURL: url)
    #expect(!result.isEmpty)
}

@Test func pyannoteAssignsSpeakersFromOverlap() {
    let engine = PyannoteEngine()
    let utterances = [
        Utterance(speaker: Speaker(id: "?"), text: "Hi", startSeconds: 0, endSeconds: 4),
        Utterance(speaker: Speaker(id: "?"), text: "There", startSeconds: 4, endSeconds: 8)
    ]
    let segments = [
        DiarizationSegment(speakerId: "1", startSeconds: 0, endSeconds: 4),
        DiarizationSegment(speakerId: "2", startSeconds: 4, endSeconds: 8)
    ]
    let result = engine.assignSpeakers(to: utterances, segments: segments)
    #expect(result[0].speaker.id == "1")
    #expect(result[1].speaker.id == "2")
}
