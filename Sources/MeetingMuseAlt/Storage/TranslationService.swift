import Foundation

/// 번역 서비스의 공통 인터페이스.
///
/// 두 구현:
///   1. `OpenAITranslator` — `gpt-4o-mini` 일괄 번역 (`meeting-muse` 웹앱의
///       `/api/translate` 라우트와 동일 시그니처/프롬프트)
///   2. `LocalNLLBTranslator` — CoreML NLLB-distilled (M3.3 후속 PR, 현재 stub)
public protocol TranslationService: Sendable {
    /// `texts` 를 `targetLang` (BCP-47 짧은 코드: en/ko/ja/zh/es/fr/de/vi) 으로 번역.
    /// 입력 순서와 동일한 출력 배열을 반환한다.
    func translate(texts: [String], targetLang: String) async throws -> [String]
}

public enum TranslationError: LocalizedError {
    case missingAPIKey
    case emptyInput
    case unsupportedLanguage(String)
    case tooManyTexts(limit: Int)
    case textTooLong(limit: Int)
    case network(String)
    case decoding(String)
    case http(status: Int, body: String)
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API 키가 필요합니다."
        case .emptyInput:
            return "번역할 텍스트가 제공되지 않았습니다."
        case .unsupportedLanguage(let lang):
            return "지원하지 않는 언어 코드입니다: \(lang)"
        case .tooManyTexts(let limit):
            return "한 번에 최대 \(limit)개의 텍스트만 번역할 수 있습니다."
        case .textTooLong(let limit):
            return "텍스트당 최대 \(limit)자까지만 번역할 수 있습니다."
        case .network(let m):
            return "네트워크 오류: \(m)"
        case .decoding(let m):
            return "응답 디코딩 실패: \(m)"
        case .http(let status, let body):
            return "HTTP \(status): \(body.prefix(200))"
        case .notImplemented:
            return "로컬 번역 엔진은 아직 구현되지 않았습니다."
        }
    }
}

/// OpenAI Chat Completions 기반 일괄 번역기 — 웹앱 `/api/translate` 와 동일 동작.
public struct OpenAITranslator: TranslationService {
    public static let supportedLanguages: [String: String] = [
        "en": "English",
        "ko": "한국어",
        "ja": "日本語",
        "zh": "中文(简体)",
        "es": "Español",
        "fr": "Français",
        "de": "Deutsch",
        "vi": "Tiếng Việt",
    ]
    public static let maxTexts = 60
    public static let maxTextLength = 1_500

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

    public func translate(texts: [String], targetLang: String) async throws -> [String] {
        if apiKey.isEmpty { throw TranslationError.missingAPIKey }
        if texts.isEmpty { throw TranslationError.emptyInput }
        if texts.count > Self.maxTexts {
            throw TranslationError.tooManyTexts(limit: Self.maxTexts)
        }
        guard let langName = Self.supportedLanguages[targetLang] else {
            throw TranslationError.unsupportedLanguage(targetLang)
        }
        let clean = texts.map { String($0.prefix(Self.maxTextLength)) }
        let numbered = clean.enumerated()
            .map { "\($0.offset + 1). \($0.element.replacingOccurrences(of: "\n", with: " "))" }
            .joined(separator: "\n")

        let systemPrompt = """
            You are a professional meeting transcript translator. Translate each numbered line to \(langName). \
            Preserve the numbering exactly. Output ONLY the numbered translations, one per line, \
            no commentary, no explanations. Keep the same number of output lines as input lines.
            """

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": numbered]
            ],
            "temperature": 0.2
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
            throw TranslationError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network("응답이 HTTPURLResponse가 아닙니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.http(status: http.statusCode, body: s)
        }

        let raw = try Self.extractText(from: data)
        return Self.parseNumberedLines(raw: raw, expectedCount: clean.count)
    }

    // MARK: - Internal helpers

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
            throw TranslationError.decoding(error.localizedDescription)
        }
    }

    /// "1. foo\n2. bar" 형태의 출력을 `expectedCount` 길이의 배열로 파싱.
    /// 누락된 슬롯은 라인 인덱스 폴백으로 채우고, 그래도 비어있으면 빈 문자열.
    static func parseNumberedLines(raw: String, expectedCount: Int) -> [String] {
        var out = Array(repeating: "", count: expectedCount)
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        // numbered 매칭: "N. text"
        let pattern = #"^\s*(\d+)\.\s*(.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for line in lines {
            let ns = line as NSString
            guard let regex,
                  let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 3
            else { continue }
            let idx = (Int(ns.substring(with: m.range(at: 1))) ?? 0) - 1
            if idx >= 0, idx < expectedCount {
                out[idx] = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            }
        }
        // 빈 슬롯에 raw line 폴백
        for i in 0..<out.count where out[i].isEmpty {
            if i < lines.count {
                out[i] = lines[i].trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }
}

/// CoreML NLLB-distilled 로컬 번역기 — 후속 PR 에서 구현.
public struct LocalNLLBTranslator: TranslationService {
    public init() {}
    public func translate(texts: [String], targetLang: String) async throws -> [String] {
        throw TranslationError.notImplemented
    }
}
