import Testing
import Foundation
@testable import MeetingMuseAlt

private func makeRecord(
    title: String = "회의",
    createdAt: Date = Date(),
    summary: String? = nil,
    utterances: [(speakerID: String, text: String)] = []
) -> MeetingRecord {
    let utts = utterances.enumerated().map { idx, pair in
        Utterance(
            speaker: Speaker(id: pair.speakerID, label: pair.speakerID),
            text: pair.text,
            startSeconds: Double(idx * 3),
            endSeconds: Double(idx * 3 + 3)
        )
    }
    return MeetingRecord(
        title: title,
        createdAt: createdAt,
        durationSeconds: 30,
        utterances: utts,
        summary: summary
    )
}

@Test func searchEmptyQueryReturnsAllRecordsAsHits() {
    let engine = MeetingSearchEngine()
    let records = [makeRecord(title: "회의 1"), makeRecord(title: "회의 2")]
    let hits = engine.search(records, query: MeetingSearchQuery(text: ""))
    #expect(hits.count == 2)
    #expect(hits.allSatisfy { !$0.hasAnyMatch })
}

@Test func searchMatchesTitleCaseInsensitive() {
    let engine = MeetingSearchEngine()
    let records = [
        makeRecord(title: "Sprint Planning"),
        makeRecord(title: "Retrospective"),
    ]
    let hits = engine.search(records, query: MeetingSearchQuery(text: "sprint"))
    #expect(hits.count == 1)
    #expect(hits.first?.titleMatched == true)
    #expect(hits.first?.record.title == "Sprint Planning")
}

@Test func searchMatchesSummary() {
    let engine = MeetingSearchEngine()
    let records = [
        makeRecord(title: "A", summary: "릴리즈 일정 결정"),
        makeRecord(title: "B", summary: "디자인 리뷰 진행"),
    ]
    let hits = engine.search(records, query: MeetingSearchQuery(text: "릴리즈"))
    #expect(hits.count == 1)
    #expect(hits.first?.summaryMatched == true)
}

@Test func searchMatchesUtteranceTextAndReturnsRanges() {
    let engine = MeetingSearchEngine()
    let records = [
        makeRecord(
            title: "회의",
            utterances: [
                ("A", "오늘은 백엔드 일정을 정리합니다."),
                ("B", "프론트엔드 일정도 정리가 필요해요."),
            ]
        )
    ]
    let hits = engine.search(records, query: MeetingSearchQuery(text: "일정"))
    #expect(hits.count == 1)
    let hit = hits.first!
    #expect(hit.utteranceHits.count == 2)
    #expect(hit.utteranceHits.allSatisfy { !$0.matchRanges.isEmpty })
}

@Test func searchSpeakerFilterRestrictsToMatchingSpeaker() {
    let engine = MeetingSearchEngine()
    let records = [
        makeRecord(
            utterances: [
                ("A", "일정 1"),
                ("B", "일정 2"),
                ("A", "일정 3"),
            ]
        )
    ]
    let hits = engine.search(records, query: MeetingSearchQuery(text: "일정", speakerID: "A"))
    #expect(hits.count == 1)
    #expect(hits.first?.utteranceHits.count == 2)
    #expect(hits.first?.utteranceHits.allSatisfy { $0.utterance.speaker.id == "A" } == true)
}

@Test func searchExcludesRecordsWithNoSpeakerMatch() {
    let engine = MeetingSearchEngine()
    let records = [
        makeRecord(title: "no speaker A", utterances: [("B", "안녕")]),
        makeRecord(title: "has speaker A", utterances: [("A", "안녕")]),
    ]
    let hits = engine.search(
        records,
        query: MeetingSearchQuery(text: "", speakerID: "A")
    )
    // 텍스트 쿼리 비어있고 speakerID만 있으면 — speakerID를 가진 회의만
    #expect(hits.count == 1)
    #expect(hits.first?.record.title == "has speaker A")
}

@Test func searchDateRangeFilter() {
    let engine = MeetingSearchEngine()
    let from = Date(timeIntervalSince1970: 1_000_000)
    let mid  = Date(timeIntervalSince1970: 2_000_000)
    let to   = Date(timeIntervalSince1970: 3_000_000)
    let records = [
        makeRecord(title: "before", createdAt: from.addingTimeInterval(-100)),
        makeRecord(title: "during", createdAt: mid),
        makeRecord(title: "after",  createdAt: to.addingTimeInterval(100)),
    ]
    let hits = engine.search(
        records,
        query: MeetingSearchQuery(text: "", fromDate: from, toDate: to)
    )
    #expect(hits.count == 1)
    #expect(hits.first?.record.title == "during")
}

@Test func findAllOccurrencesReturnsAllMatches() {
    let ranges = MeetingSearchEngine.findAllOccurrences(of: "ab", in: "ababcab")
    #expect(ranges.count == 3)
    #expect(ranges[0].location == 0)
    #expect(ranges[1].location == 2)
    #expect(ranges[2].location == 5)
}

@Test func findAllOccurrencesEmptyNeedleReturnsEmpty() {
    let ranges = MeetingSearchEngine.findAllOccurrences(of: "", in: "haystack")
    #expect(ranges.isEmpty)
}

@Test func findAllOccurrencesCaseInsensitive() {
    let ranges = MeetingSearchEngine.findAllOccurrences(of: "Hello", in: "say hello and HELLO")
    #expect(ranges.count == 2)
}

@Test func searchQueryIsEmptyConsidersFilters() {
    #expect(MeetingSearchQuery(text: "").isEmpty)
    #expect(MeetingSearchQuery(text: "   ").isEmpty)
    #expect(!MeetingSearchQuery(text: "x").isEmpty)
    #expect(!MeetingSearchQuery(text: "", speakerID: "A").isEmpty)
    #expect(!MeetingSearchQuery(text: "", fromDate: Date()).isEmpty)
}
