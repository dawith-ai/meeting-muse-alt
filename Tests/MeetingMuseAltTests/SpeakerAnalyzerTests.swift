import Testing
import Foundation
@testable import MeetingMuseAlt

private func u(_ speaker: String, _ start: Double, _ end: Double) -> Utterance {
    Utterance(
        speaker: Speaker(id: speaker, label: speaker),
        text: "text",
        startSeconds: start,
        endSeconds: end
    )
}

@Test func analyzerEmptyReturnsEmpty() {
    let a = SpeakerAnalyzer.analyze([])
    #expect(a.totalUtterances == 0)
    #expect(a.totalSeconds == 0)
    #expect(a.distinctSpeakers == 0)
    #expect(a.speakers.isEmpty)
}

@Test func analyzerAggregatesByID() {
    let utts = [
        u("A", 0, 10),
        u("B", 10, 20),
        u("A", 20, 25),
    ]
    let a = SpeakerAnalyzer.analyze(utts)
    #expect(a.totalUtterances == 3)
    #expect(a.distinctSpeakers == 2)
    #expect(a.totalSeconds == 25)

    let aStat = a.speakers.first { $0.speakerID == "A" }!
    #expect(aStat.totalSeconds == 15)
    #expect(aStat.utteranceCount == 2)
    #expect(aStat.fraction == 0.6)
    #expect(aStat.averageUtteranceSeconds == 7.5)
}

@Test func analyzerSortsByFractionDescending() {
    let utts = [
        u("C", 0, 1),
        u("A", 1, 11),
        u("B", 11, 16),
    ]
    let a = SpeakerAnalyzer.analyze(utts)
    #expect(a.speakers.map(\.speakerID) == ["A", "B", "C"])
}

@Test func diversityIndexBoundaries() {
    let only = [SpeakerStat(speakerID: "A", label: "A", totalSeconds: 10, utteranceCount: 1, fraction: 1.0)]
    #expect(SpeakerAnalyzer.diversityIndex(only) == 0.0)

    let mixed = [
        SpeakerStat(speakerID: "A", label: "A", totalSeconds: 6, utteranceCount: 2, fraction: 0.6),
        SpeakerStat(speakerID: "B", label: "B", totalSeconds: 4, utteranceCount: 2, fraction: 0.4),
    ]
    #expect(abs(SpeakerAnalyzer.diversityIndex(mixed) - 0.4) < 1e-9)
}

@Test func formatDurationHandlesHoursMinutesSeconds() {
    #expect(SpeakerAnalyzer.formatDuration(0) == "0초")
    #expect(SpeakerAnalyzer.formatDuration(45) == "45초")
    #expect(SpeakerAnalyzer.formatDuration(125) == "2분 5초")
    #expect(SpeakerAnalyzer.formatDuration(3725) == "1시간 2분")
}
