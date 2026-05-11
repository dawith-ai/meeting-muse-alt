import Testing
import Foundation
@testable import MeetingMuseAlt

/// Builds a fresh in-memory `MeetingPersistence` for each test so they cannot
/// observe each other's writes.
@MainActor
private func makePersistence() throws -> MeetingPersistence {
    try MeetingPersistence(inMemory: true)
}

private func sampleUtterances() -> [Utterance] {
    [
        Utterance(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            speaker: Speaker(id: "1", label: "Alice"),
            text: "안녕하세요",
            startSeconds: 0,
            endSeconds: 2.5,
            confidence: 0.92
        ),
        Utterance(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            speaker: Speaker(id: "2", label: "Bob"),
            text: "반갑습니다",
            startSeconds: 2.5,
            endSeconds: 5.0,
            confidence: 0.88
        )
    ]
}

@Test @MainActor
func saveThenAllReturnsRecordWithDecodedUtterances() throws {
    let persistence = try makePersistence()
    let repo = MeetingRepository(persistence: persistence)

    let utterances = sampleUtterances()
    let saved = try repo.save(
        title: "회의 1",
        utterances: utterances,
        durationSeconds: 5.0
    )

    let all = try repo.all()
    #expect(all.count == 1)
    #expect(all.first?.id == saved.id)
    let fetchedUtterances = all.first?.utterances ?? []
    #expect(fetchedUtterances.count == 2)
    #expect(fetchedUtterances.first?.text == "안녕하세요")
    #expect(fetchedUtterances.last?.speaker.label == "Bob")
}

@Test @MainActor
func findById_returnsMatchingRecord() throws {
    let persistence = try makePersistence()
    let repo = MeetingRepository(persistence: persistence)

    let saved = try repo.save(
        title: "찾기 테스트",
        utterances: sampleUtterances(),
        durationSeconds: 12.5,
        language: "ko",
        summary: "요약입니다"
    )

    let found = try repo.find(id: saved.id)
    #expect(found != nil)
    #expect(found?.title == "찾기 테스트")
    #expect(found?.durationSeconds == 12.5)
    #expect(found?.summary == "요약입니다")
}

@Test @MainActor
func deleteRemovesRecordFromAll() throws {
    let persistence = try makePersistence()
    let repo = MeetingRepository(persistence: persistence)

    let saved = try repo.save(
        title: "삭제 대상",
        utterances: [],
        durationSeconds: 1.0
    )
    #expect(try repo.all().count == 1)

    try repo.delete(saved)

    #expect(try repo.all().isEmpty)
    #expect(try repo.find(id: saved.id) == nil)
}

@Test @MainActor
func updatePersistsTitleChange() throws {
    let persistence = try makePersistence()
    let repo = MeetingRepository(persistence: persistence)

    var saved = try repo.save(
        title: "원래 제목",
        utterances: [],
        durationSeconds: 3.0
    )
    saved.title = "변경된 제목"
    try repo.update(saved)

    let refetched = try repo.find(id: saved.id)
    #expect(refetched?.title == "변경된 제목")
}

@Test @MainActor
func utterancesJSONRoundTripPreservesSpeakerAndTimestamps() throws {
    let persistence = try makePersistence()
    let repo = MeetingRepository(persistence: persistence)

    let original = sampleUtterances()
    let saved = try repo.save(
        title: "라운드트립",
        utterances: original,
        durationSeconds: 5.0
    )

    let refetched = try repo.find(id: saved.id)
    let decoded = refetched?.utterances ?? []

    #expect(decoded.count == original.count)
    for (lhs, rhs) in zip(decoded, original) {
        #expect(lhs.id == rhs.id)
        #expect(lhs.speaker.id == rhs.speaker.id)
        #expect(lhs.speaker.label == rhs.speaker.label)
        #expect(lhs.startSeconds == rhs.startSeconds)
        #expect(lhs.endSeconds == rhs.endSeconds)
        #expect(lhs.confidence == rhs.confidence)
        #expect(lhs.text == rhs.text)
    }
}

@Test @MainActor
func allReturnsRecordsSortedByCreatedAtDescending() throws {
    let persistence = try makePersistence()
    let repo = MeetingRepository(persistence: persistence)

    let older = try repo.save(
        title: "old",
        utterances: [],
        durationSeconds: 1.0,
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let newer = try repo.save(
        title: "new",
        utterances: [],
        durationSeconds: 1.0,
        createdAt: Date(timeIntervalSince1970: 2_000)
    )

    let all = try repo.all()
    #expect(all.count == 2)
    #expect(all.first?.id == newer.id)
    #expect(all.last?.id == older.id)
}
