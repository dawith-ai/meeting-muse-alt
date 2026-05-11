import Foundation

/// 회의록 요약 서비스의 공통 인터페이스.
///
/// 두 가지 구현을 두어 어디서나 동작하도록 한다:
///   1. `OpenAISummarizer` — `gpt-4o-mini` 등 원격 호출 (API 키 필요, 인터넷 필요)
///   2. `LocalLlamaSummarizer` — llama.cpp 로컬 추론 (M3.1 후속 PR, 현재 stub)
public protocol SummarizationService: Sendable {
    /// 전사된 발화 리스트와 회의 메타데이터로부터 마크다운 요약을 생성한다.
    func summarize(
        utterances: [Utterance],
        title: String?,
        languageHint: String
    ) async throws -> String
}

public enum SummarizationError: LocalizedError {
    case missingAPIKey
    case emptyUtterances
    case network(String)
    case decoding(String)
    case http(status: Int, body: String)
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API 키가 필요합니다. 설정에서 입력해주세요."
        case .emptyUtterances:
            return "요약할 발화가 없습니다."
        case .network(let m):
            return "네트워크 오류: \(m)"
        case .decoding(let m):
            return "응답 디코딩 실패: \(m)"
        case .http(let status, let body):
            return "HTTP \(status): \(body.prefix(200))"
        case .notImplemented:
            return "로컬 요약 엔진은 아직 구현되지 않았습니다."
        }
    }
}
