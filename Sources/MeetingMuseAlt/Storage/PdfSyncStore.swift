import Foundation
import SwiftUI

/// 현재 활성 PDF 동기화 세션의 상태를 보관하는 ObservableObject.
///
/// SwiftUI 뷰는 이 스토어를 관찰하면서 PDF 페이지 ↔ 녹음 타임스탬프 마크를
/// 추가/삭제하고, 재생 중 현재 타임스탬프에 해당하는 페이지를 자동으로
/// 표시한다. 파일 영속화는 `MeetingRecord.pdfFilePath` / `pdfPageMarks` 에
/// 위임한다 — `PdfSyncStore` 자체는 인메모리 상태일 뿐이다.
@MainActor
public final class PdfSyncStore: ObservableObject {
    @Published public private(set) var pdfURL: URL?
    @Published public private(set) var totalPages: Int
    @Published public private(set) var marks: [PdfPageMark]
    @Published public var currentPage: Int

    public init(
        pdfURL: URL? = nil,
        totalPages: Int = 0,
        marks: [PdfPageMark] = [],
        currentPage: Int = 1
    ) {
        self.pdfURL = pdfURL
        self.totalPages = max(0, totalPages)
        self.marks = marks.sorted()
        self.currentPage = max(1, currentPage)
    }

    // MARK: - PDF lifecycle

    public func loadPdf(url: URL, totalPages: Int) {
        self.pdfURL = url
        self.totalPages = max(0, totalPages)
        self.marks = []
        self.currentPage = 1
    }

    public func clearPdf() {
        self.pdfURL = nil
        self.totalPages = 0
        self.marks = []
        self.currentPage = 1
    }

    // MARK: - Mark CRUD

    /// 같은 페이지의 기존 마크가 있으면 교체 (upsert), 없으면 추가.
    public func upsertMark(pageNumber: Int, timestampSeconds: Double) {
        let safePage = clampPage(pageNumber)
        let mark = PdfPageMark(pageNumber: safePage, timestampSeconds: timestampSeconds)
        var next = marks.filter { $0.pageNumber != safePage }
        next.append(mark)
        next.sort()
        marks = next
    }

    public func removeMark(forPage page: Int) {
        marks.removeAll { $0.pageNumber == page }
    }

    public func clearMarks() {
        marks = []
    }

    public func mark(forPage page: Int) -> PdfPageMark? {
        marks.first { $0.pageNumber == page }
    }

    // MARK: - Playback query

    /// 주어진 타임스탬프에 자동으로 표시되어야 할 페이지.
    ///
    /// - 마크가 비어 있으면 `nil`
    /// - `timeSeconds` 이전의 가장 최근 마크의 페이지를 반환
    /// - 모든 마크가 `timeSeconds` 이후라면 가장 빠른 마크의 페이지를 반환
    public func currentPage(at timeSeconds: Double) -> Int? {
        guard !marks.isEmpty else { return nil }
        let sorted = marks.sorted()
        // 가장 최근 (timestamp <= time) 마크 찾기
        var lastPage: Int?
        for mark in sorted {
            if mark.timestampSeconds <= timeSeconds {
                lastPage = mark.pageNumber
            } else {
                break
            }
        }
        return lastPage ?? sorted.first?.pageNumber
    }

    /// 재생 위치 업데이트 — 자동으로 `currentPage` 가 마크에 따라 따라간다.
    public func tick(timeSeconds: Double) {
        if let page = currentPage(at: timeSeconds) {
            if currentPage != page {
                currentPage = page
            }
        }
    }

    // MARK: - Snapshot (영속화용)

    public func snapshot() -> (pdfURL: URL?, marks: [PdfPageMark]) {
        (pdfURL: pdfURL, marks: marks)
    }

    public func restore(pdfURL: URL?, totalPages: Int, marks: [PdfPageMark]) {
        self.pdfURL = pdfURL
        self.totalPages = max(0, totalPages)
        self.marks = marks.sorted()
        self.currentPage = max(1, currentPage(at: 0) ?? 1)
    }

    // MARK: - Helpers

    private func clampPage(_ page: Int) -> Int {
        if totalPages > 0 {
            return min(max(1, page), totalPages)
        }
        return max(1, page)
    }
}
