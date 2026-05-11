import Testing
import Foundation
@testable import MeetingMuseAlt

@MainActor
@Test func emptyStoreHasNoCurrentPage() {
    let store = PdfSyncStore()
    #expect(store.currentPage(at: 0) == nil)
    #expect(store.currentPage(at: 9999) == nil)
}

@MainActor
@Test func loadPdfResetsMarksAndPage() {
    let store = PdfSyncStore(
        pdfURL: URL(fileURLWithPath: "/tmp/a.pdf"),
        totalPages: 10,
        marks: [PdfPageMark(pageNumber: 3, timestampSeconds: 5)],
        currentPage: 3
    )
    store.loadPdf(url: URL(fileURLWithPath: "/tmp/b.pdf"), totalPages: 20)
    #expect(store.marks.isEmpty)
    #expect(store.currentPage == 1)
    #expect(store.totalPages == 20)
}

@MainActor
@Test func upsertMarkReplacesExistingPageMark() {
    let store = PdfSyncStore(totalPages: 5)
    store.upsertMark(pageNumber: 2, timestampSeconds: 10)
    store.upsertMark(pageNumber: 2, timestampSeconds: 25) // 같은 페이지 → 교체
    #expect(store.marks.count == 1)
    #expect(store.marks.first?.timestampSeconds == 25)
}

@MainActor
@Test func marksAreSortedByTimestamp() {
    let store = PdfSyncStore(totalPages: 10)
    store.upsertMark(pageNumber: 5, timestampSeconds: 30)
    store.upsertMark(pageNumber: 2, timestampSeconds: 10)
    store.upsertMark(pageNumber: 7, timestampSeconds: 20)
    #expect(store.marks.map(\.pageNumber) == [2, 7, 5])
}

@MainActor
@Test func currentPageAtTimeReturnsLatestPreviousMark() {
    let store = PdfSyncStore(totalPages: 10)
    store.upsertMark(pageNumber: 1, timestampSeconds: 0)
    store.upsertMark(pageNumber: 2, timestampSeconds: 10)
    store.upsertMark(pageNumber: 3, timestampSeconds: 20)
    store.upsertMark(pageNumber: 4, timestampSeconds: 30)
    #expect(store.currentPage(at: 0) == 1)
    #expect(store.currentPage(at: 5) == 1)
    #expect(store.currentPage(at: 10) == 2)
    #expect(store.currentPage(at: 15) == 2)
    #expect(store.currentPage(at: 25) == 3)
    #expect(store.currentPage(at: 999) == 4)
}

@MainActor
@Test func currentPageBeforeFirstMarkReturnsFirstPage() {
    let store = PdfSyncStore(totalPages: 10)
    store.upsertMark(pageNumber: 5, timestampSeconds: 30)
    // 모든 마크가 t=0 이후이지만 가장 빠른 마크의 페이지를 반환
    #expect(store.currentPage(at: 0) == 5)
}

@MainActor
@Test func tickUpdatesCurrentPage() {
    let store = PdfSyncStore(totalPages: 10)
    store.upsertMark(pageNumber: 2, timestampSeconds: 10)
    store.upsertMark(pageNumber: 3, timestampSeconds: 20)
    store.tick(timeSeconds: 15)
    #expect(store.currentPage == 2)
    store.tick(timeSeconds: 22)
    #expect(store.currentPage == 3)
}

@MainActor
@Test func removeMarkRemovesByPage() {
    let store = PdfSyncStore(totalPages: 10)
    store.upsertMark(pageNumber: 1, timestampSeconds: 0)
    store.upsertMark(pageNumber: 2, timestampSeconds: 10)
    store.removeMark(forPage: 1)
    #expect(store.marks.count == 1)
    #expect(store.marks.first?.pageNumber == 2)
}

@MainActor
@Test func clearPdfResetsEverything() {
    let store = PdfSyncStore(
        pdfURL: URL(fileURLWithPath: "/tmp/x.pdf"),
        totalPages: 10,
        marks: [PdfPageMark(pageNumber: 1, timestampSeconds: 0)],
        currentPage: 5
    )
    store.clearPdf()
    #expect(store.pdfURL == nil)
    #expect(store.totalPages == 0)
    #expect(store.marks.isEmpty)
    #expect(store.currentPage == 1)
}

@MainActor
@Test func upsertMarkClampsPageNumberToTotalPages() {
    let store = PdfSyncStore(totalPages: 5)
    store.upsertMark(pageNumber: 10, timestampSeconds: 5)
    store.upsertMark(pageNumber: 0, timestampSeconds: 6)
    #expect(store.marks.count == 2)
    #expect(store.marks.first(where: { $0.timestampSeconds == 5 })?.pageNumber == 5)
    #expect(store.marks.first(where: { $0.timestampSeconds == 6 })?.pageNumber == 1)
}

@Test func meetingRecordDecodesLegacyPayloadWithoutPdfFields() throws {
    let legacyJSON = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "title": "옛 회의",
      "createdAt": "2025-01-01T00:00:00Z",
      "durationSeconds": 60,
      "language": "ko",
      "utterances": []
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(MeetingRecord.self, from: legacyJSON)
    #expect(record.title == "옛 회의")
    #expect(record.pdfFilePath == nil)
    #expect(record.pdfPageMarks.isEmpty)
}

@Test func pdfPageMarkCodableRoundTrip() throws {
    let original = PdfPageMark(pageNumber: 3, timestampSeconds: 42.5)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PdfPageMark.self, from: data)
    #expect(decoded.pageNumber == 3)
    #expect(decoded.timestampSeconds == 42.5)
    #expect(decoded.id == original.id)
}
