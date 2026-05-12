import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func contentSectionAllCasesContainsAllTabs() {
    let labels = ContentSection.allCases.map(\.label)
    #expect(labels == ["녹음", "발표 자료", "분석", "Ask AI", "액션 아이템", "검색", "라이브러리", "설정"])
}

@Test func contentSectionIconsAreNonEmpty() {
    for s in ContentSection.allCases {
        #expect(!s.icon.isEmpty)
    }
}

@MainActor
@Test func recordingViewModelSavesEmptyMeetingThroughRepository() throws {
    let vm = RecordingViewModel()
    let persistence = try MeetingPersistence(inMemory: true)
    let repo = MeetingRepository(persistence: persistence)

    let saved = try vm.saveCurrentMeeting(repository: repo, title: "테스트 회의")
    #expect(saved.title == "테스트 회의")

    let all = try repo.all()
    #expect(all.count == 1)
    #expect(all.first?.id == saved.id)
}

@MainActor
@Test func recordingViewModelSaveIncludesPdfMarksWhenPresent() throws {
    let vm = RecordingViewModel()
    let persistence = try MeetingPersistence(inMemory: true)
    let repo = MeetingRepository(persistence: persistence)

    let pdfURL = URL(fileURLWithPath: "/tmp/slides.pdf")
    vm.pdfSyncStore.loadPdf(url: pdfURL, totalPages: 10)
    vm.pdfSyncStore.upsertMark(pageNumber: 3, timestampSeconds: 12)
    vm.pdfSyncStore.upsertMark(pageNumber: 5, timestampSeconds: 28)

    let saved = try vm.saveCurrentMeeting(repository: repo, title: "PDF 회의")
    #expect(saved.pdfFilePath == "/tmp/slides.pdf")
    #expect(saved.pdfPageMarks.count == 2)

    // 다시 조회해도 마크가 보존
    let refetched = try repo.find(id: saved.id)
    #expect(refetched?.pdfPageMarks.count == 2)
    #expect(refetched?.pdfPageMarks.contains(where: { $0.pageNumber == 3 }) == true)
}

@MainActor
@Test func recordingViewModelResetClearsPdfMarks() {
    let vm = RecordingViewModel()
    vm.pdfSyncStore.upsertMark(pageNumber: 1, timestampSeconds: 5)
    vm.reset()
    #expect(vm.pdfSyncStore.marks.isEmpty)
    #expect(vm.elapsedSeconds == 0)
}
