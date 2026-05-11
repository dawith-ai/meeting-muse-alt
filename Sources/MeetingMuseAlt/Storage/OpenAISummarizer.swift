import Foundation

/// OpenAI Chat Completions API 기반 요약기.
///
/// `meeting-muse` 웹앱의 `/api/summarize` 와 동일한 프롬프트 전략을 사용한다.
/// API 키는 호출 시점에 주입 — 영속 저장은 호출자(`AppSettings` 또는 keychain)
/// 가 담당한다.
public struct OpenAISummarizer: SummarizationService {
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

    public func summarize(
        utterances: [Utterance],
        title: String?,
        languageHint: String
    ) async throws -> String {
        if apiKey.isEmpty { throw SummarizationError.missingAPIKey }
        if utterances.isEmpty { throw SummarizationError.emptyUtterances }

        let transcript = Self.formatTranscript(utterances)
        let body = Self.makeRequestBody(
            model: model,
            transcript: transcript,
            title: title,
            languageHint: languageHint
        )

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SummarizationError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SummarizationError.network("응답이 HTTPURLResponse가 아닙니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw SummarizationError.http(status: http.statusCode, body: bodyText)
        }

        return try Self.extractText(from: data)
    }

    // MARK: - Internal helpers (테스트에서 접근 가능하도록 internal)

    static func formatTranscript(_ utterances: [Utterance]) -> String {
        utterances.map { utt in
            "[\(utt.timestampLabel)] \(utt.speaker.label): \(utt.text)"
        }.joined(separator: "\n")
    }

    static func makeRequestBody(
        model: String,
        transcript: String,
        title: String?,
        languageHint: String
    ) -> Data {
        let langName: String = {
            switch languageHint {
            case "ko": return "한국어"
            case "en": return "English"
            case "ja": return "日本語"
            case "zh": return "中文"
            default:   return languageHint
            }
        }()
        let titleLine = title.map { "회의 제목: \($0)\n\n" } ?? ""
        let systemPrompt = """
            당신은 회의록 요약 전문가입니다. 아래 전사 내용을 \(langName) 마크다운으로 요약하세요.
            다음 섹션을 포함하세요:
            ## 핵심 요약
            ## 주요 논의 사항
            ## 결정 사항
            ## 액션 아이템 (담당자/기한)
            전사에 없는 내용은 추측하지 마세요.
            """
        let userPrompt = "\(titleLine)전사:\n\(transcript)"

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ],
            "temperature": 0.3
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
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
            throw SummarizationError.decoding(error.localizedDescription)
        }
    }
}

/// llama.cpp 기반 로컬 요약기 — 후속 PR 에서 구현.
public struct LocalLlamaSummarizer: SummarizationService {
    public init() {}
    public func summarize(
        utterances: [Utterance],
        title: String?,
        languageHint: String
    ) async throws -> String {
        throw SummarizationError.notImplemented
    }
}
