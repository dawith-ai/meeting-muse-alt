import Foundation

/// 발표 자료 PDF의 한 페이지가 녹음의 특정 시각에 매핑되었음을 나타내는 마크.
///
/// 같은 `pageNumber` 에 대해 가장 최근 마크만 의미가 있도록 `PdfSyncStore` 가
/// upsert 의미로 다룬다.
public struct PdfPageMark: Identifiable, Codable, Hashable, Sendable, Comparable {
    public var id: UUID
    /// 1-based PDF 페이지 번호.
    public var pageNumber: Int
    /// 녹음 시작 시점으로부터의 초.
    public var timestampSeconds: Double

    public init(
        id: UUID = UUID(),
        pageNumber: Int,
        timestampSeconds: Double
    ) {
        self.id = id
        self.pageNumber = max(1, pageNumber)
        self.timestampSeconds = max(0, timestampSeconds)
    }

    /// 타임라인 정렬 비교 — `timestampSeconds` 우선, 동률이면 `pageNumber`.
    public static func < (lhs: PdfPageMark, rhs: PdfPageMark) -> Bool {
        if lhs.timestampSeconds != rhs.timestampSeconds {
            return lhs.timestampSeconds < rhs.timestampSeconds
        }
        return lhs.pageNumber < rhs.pageNumber
    }

    public var timestampLabel: String {
        let total = Int(timestampSeconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
