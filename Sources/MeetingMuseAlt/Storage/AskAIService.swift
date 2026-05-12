import Foundation

/// 회의 내용에 대한 자연어 Q&A.
public struct AskAIMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Hashable, Sendable { case user, assistant }
    public var id: UUID
    public var role: Role
    public var content: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public protocol AskAIService: Sendable {
    /// 이전 대화 + 새 질문 → 어시스턴트 응답.
    func ask(
        utterances: [Utterance],
        history: [AskAIMessage],
        question: String,
        languageHint: String
    ) async throws -> String
}

public enum AskAIError: LocalizedError {
    case missingAPIKey
    case emptyQuestion
    case network(String)
    case decoding(String)
    case http(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "OpenAI API 키가 필요합니다."
        case .emptyQuestion: return "질문이 비어 있습니다."
        case .network(let m): return "네트워크 오류: \(m)"
        case .decoding(let m): return "응답 디코딩 실패: \(m)"
        case .http(let s, let b): return "HTTP \(s): \(b.prefix(200))"
        }
    }
}

/// OpenAI Chat Completions 기반 Q&A. (`meeting-muse` 웹앱 `/api/ask-ai` 와 동등 동작)
public struct OpenAIAskAI: AskAIService {
    public let apiKey: String
    public let model: String
    public let endpoint: URL
    public let session: URLSession

    public init(
        apiKey: String,
        model: String = "gpt-4o-mini",
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    public func ask(
        utterances: [Utterance],
        history: [AskAIMessage],
        question: String,
        languageHint: String
    ) async throws -> String {
        if apiKey.isEmpty { throw AskAIError.missingAPIKey }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AskAIError.emptyQuestion }

        let langName: String = {
            switch languageHint {
            case "ko": return "한국어"
            case "en": return "English"
            case "ja": return "日本語"
            case "zh": return "中文"
            default:   return languageHint
            }
        }()

        let transcript = Self.formatTranscript(utterances)
        let systemPrompt = """
            당신은 회의 내용을 깊이 이해하고 정확하게 답변하는 어시스턴트입니다.
            제공된 전사 내용 안에서만 답하세요. 전사에 없는 사실은 추측하지 말고 \
            "전사에서 확인할 수 없음" 이라고 답하세요. 답변은 \(langName) 로 작성하세요.
            전사:
            \(transcript)
            """

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in history.suffix(20) {
            messages.append([
                "role": msg.role.rawValue,
                "content": msg.content
            ])
        }
        messages.append(["role": "user", "content": trimmed])

        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AskAIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AskAIError.network("응답이 HTTPURLResponse가 아닙니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw AskAIError.http(status: http.statusCode, body: s)
        }

        return try Self.extractText(from: data)
    }

    // MARK: - Internal helpers

    static func formatTranscript(_ utterances: [Utterance]) -> String {
        utterances.prefix(500).map { utt in
            "[\(utt.timestampLabel)] \(utt.speaker.label): \(utt.text)"
        }.joined(separator: "\n")
    }

    static func extractText(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        do {
            let r = try JSONDecoder().decode(Response.self, from: data)
            return r.choices.first?.message.content ?? ""
        } catch {
            throw AskAIError.decoding(error.localizedDescription)
        }
    }
}
