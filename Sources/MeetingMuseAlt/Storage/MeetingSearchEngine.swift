import Foundation

/// 회의록 전문 검색 쿼리.
public struct MeetingSearchQuery: Hashable, Sendable {
    /// 대소문자 무시 substring 매칭 — 공백만 있거나 빈 문자열이면 모든 회의 반환.
    public var text: String
    /// 특정 화자 ID로만 필터 (nil = 전체).
    public var speakerID: String?
    /// 시작 날짜 (포함). nil = 제한 없음.
    public var fromDate: Date?
    /// 종료 날짜 (포함). nil = 제한 없음.
    public var toDate: Date?

    public init(
        text: String = "",
        speakerID: String? = nil,
        fromDate: Date? = nil,
        toDate: Date? = nil
    ) {
        self.text = text
        self.speakerID = speakerID
        self.fromDate = fromDate
        self.toDate = toDate
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 텍스트 쿼리 없이 필터만 적용해도 검색은 유효.
    public var isEmpty: Bool {
        trimmedText.isEmpty && speakerID == nil && fromDate == nil && toDate == nil
    }
}

/// 한 발화의 매치 결과.
public struct UtteranceHit: Hashable, Sendable {
    public var utteranceIndex: Int
    public var utterance: Utterance
    /// `utterance.text` 안에서의 매치 NSRange (대소문자 무시 첫 발견부터 끝까지).
    public var matchRanges: [NSRange]

    public init(utteranceIndex: Int, utterance: Utterance, matchRanges: [NSRange]) {
        self.utteranceIndex = utteranceIndex
        self.utterance = utterance
        self.matchRanges = matchRanges
    }
}

/// 한 회의의 검색 결과.
public struct MeetingSearchHit: Identifiable, Hashable, Sendable {
    public var record: MeetingRecord
    public var titleMatched: Bool
    public var summaryMatched: Bool
    public var utteranceHits: [UtteranceHit]

    public var id: UUID { record.id }

    public init(
        record: MeetingRecord,
        titleMatched: Bool = false,
        summaryMatched: Bool = false,
        utteranceHits: [UtteranceHit] = []
    ) {
        self.record = record
        self.titleMatched = titleMatched
        self.summaryMatched = summaryMatched
        self.utteranceHits = utteranceHits
    }

    /// 매치된 발화/타이틀/요약 중 하나라도 있으면 true.
    public var hasAnyMatch: Bool {
        titleMatched || summaryMatched || !utteranceHits.isEmpty
    }
}

/// 전문 검색 엔진. 인메모리 `[MeetingRecord]` 위에서 동작하므로
/// 100여 건 단위까지는 즉시 응답한다. 대규모 라이브러리는 향후 SQLite FTS5 로 이전.
public struct MeetingSearchEngine: Sendable {
    public init() {}

    public func search(
        _ records: [MeetingRecord],
        query: MeetingSearchQuery
    ) -> [MeetingSearchHit] {
        // 1) 날짜/화자 필터 (텍스트 무관)
        let datesFiltered = records.filter { rec in
            if let from = query.fromDate, rec.createdAt < from { return false }
            if let to = query.toDate, rec.createdAt > to { return false }
            if let sid = query.speakerID {
                return rec.utterances.contains { $0.speaker.id == sid }
            }
            return true
        }

        let trimmed = query.trimmedText
        // 텍스트 쿼리가 비었으면 — 필터만 적용한 모든 회의를 매치 없음 hit 로 반환
        guard !trimmed.isEmpty else {
            return datesFiltered.map { rec in
                let utteranceHits: [UtteranceHit]
                if let sid = query.speakerID {
                    utteranceHits = rec.utterances.enumerated().compactMap { idx, utt in
                        utt.speaker.id == sid
                            ? UtteranceHit(utteranceIndex: idx, utterance: utt, matchRanges: [])
                            : nil
                    }
                } else {
                    utteranceHits = []
                }
                return MeetingSearchHit(
                    record: rec,
                    titleMatched: false,
                    summaryMatched: false,
                    utteranceHits: utteranceHits
                )
            }
        }

        // 2) 텍스트 매칭 (case-insensitive)
        var out: [MeetingSearchHit] = []
        for rec in datesFiltered {
            let titleMatched = rec.title.range(of: trimmed, options: .caseInsensitive) != nil
            let summaryMatched = rec.summary?.range(of: trimmed, options: .caseInsensitive) != nil

            var utteranceHits: [UtteranceHit] = []
            for (idx, utt) in rec.utterances.enumerated() {
                if let sid = query.speakerID, utt.speaker.id != sid { continue }
                let ranges = Self.findAllOccurrences(of: trimmed, in: utt.text)
                if !ranges.isEmpty {
                    utteranceHits.append(UtteranceHit(
                        utteranceIndex: idx,
                        utterance: utt,
                        matchRanges: ranges
                    ))
                }
            }

            let hit = MeetingSearchHit(
                record: rec,
                titleMatched: titleMatched,
                summaryMatched: summaryMatched,
                utteranceHits: utteranceHits
            )
            if hit.hasAnyMatch {
                out.append(hit)
            }
        }
        return out
    }

    /// `needle` 의 모든 occurrence를 case-insensitive 로 찾는다.
    public static func findAllOccurrences(of needle: String, in haystack: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        var ranges: [NSRange] = []
        let ns = haystack as NSString
        var searchStart = 0
        let length = ns.length
        while searchStart < length {
            let remainingRange = NSRange(location: searchStart, length: length - searchStart)
            let r = ns.range(of: needle, options: .caseInsensitive, range: remainingRange)
            if r.location == NSNotFound { break }
            ranges.append(r)
            searchStart = r.location + max(1, r.length)
        }
        return ranges
    }
}
