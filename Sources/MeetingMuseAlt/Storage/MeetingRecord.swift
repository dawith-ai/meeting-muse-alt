import Foundation

/// 영구 저장되는 회의 레코드 (값 타입).
///
/// SwiftData 매크로(`@Model`)는 Swift Command Line Tools 빌드 환경에서
/// 플러그인이 로드되지 않으므로, JSON-Codable 기반의 파일 영속화 레이어로
/// 구현했습니다. 향후 Xcode App Target(M2.4) 전환 시점에 SwiftData 또는
/// GRDB로 마이그레이션 가능하도록 도메인 모델은 storage-agnostic하게 둡니다.
public struct MeetingRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var durationSeconds: Double
    /// 파일 시스템 경로 (`file://` URL 문자열이 아님)
    public var audioFilePath: String?
    public var utterances: [Utterance]
    /// BCP-47 언어 태그 ("ko", "en")
    public var language: String
    /// 옵셔널 AI 요약
    public var summary: String?
    /// 첨부된 발표 자료 PDF의 파일 시스템 경로
    public var pdfFilePath: String?
    /// PDF 페이지 ↔ 녹음 타임스탬프 마크
    public var pdfPageMarks: [PdfPageMark]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        durationSeconds: Double,
        audioFilePath: String? = nil,
        utterances: [Utterance] = [],
        language: String = "ko",
        summary: String? = nil,
        pdfFilePath: String? = nil,
        pdfPageMarks: [PdfPageMark] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioFilePath = audioFilePath
        self.utterances = utterances
        self.language = language
        self.summary = summary
        self.pdfFilePath = pdfFilePath
        self.pdfPageMarks = pdfPageMarks
    }

    // MARK: - Codable (스키마 드리프트 내성)

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, durationSeconds, audioFilePath,
             utterances, language, summary, pdfFilePath, pdfPageMarks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        audioFilePath = try c.decodeIfPresent(String.self, forKey: .audioFilePath)
        utterances = try c.decodeIfPresent([Utterance].self, forKey: .utterances) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "ko"
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        pdfFilePath = try c.decodeIfPresent(String.self, forKey: .pdfFilePath)
        pdfPageMarks = try c.decodeIfPresent([PdfPageMark].self, forKey: .pdfPageMarks) ?? []
    }
}
