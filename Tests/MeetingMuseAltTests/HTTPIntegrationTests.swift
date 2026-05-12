import Testing
import Foundation
@testable import MeetingMuseAlt

/// 요청 본문을 Data 로 추출 (테스트가 직접 URLSession 으로 보낸 경우 httpBody,
/// stream 인 경우 bodyStream).
private func extractBody(_ req: URLRequest) -> Data {
    if let data = req.httpBody { return data }
    guard let stream = req.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var out = Data()
    let bufSize = 4096
    var buf = [UInt8](repeating: 0, count: bufSize)
    while stream.hasBytesAvailable {
        let n = stream.read(&buf, maxLength: bufSize)
        if n <= 0 { break }
        out.append(buf, count: n)
    }
    return out
}

/// MockURLProtocol 은 process-wide static handler 를 사용하므로 병렬 실행 시
/// race 가 발생한다. 같은 suite 안에서 직렬화한다.
@Suite(.serialized)
struct HTTPIntegrationSuite {
    // MARK: - OpenAI Summarizer

    @Test func summarizerEndToEndReturnsAssistantContent() async throws {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-fake")
            let body = extractBody(req)
            if let dict = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
               let messages = dict["messages"] as? [[String: Any]] {
                #expect(messages.count == 2)
                let user = messages.last?["content"] as? String ?? ""
                #expect(user.contains("[00:00]"))
            }
            return MockURLProtocol.jsonResponse(
                "{\"choices\":[{\"message\":{\"content\":\"## 요약\\n핵심 결정 3건.\"}}]}",
                url: url
            )
        }
        defer { MockURLProtocol.requestHandler = nil }

        let summarizer = OpenAISummarizer(apiKey: "sk-fake", endpoint: url, session: session)
        let result = try await summarizer.summarize(
            utterances: [
                Utterance(speaker: Speaker(id: "A", label: "Alice"), text: "안녕", startSeconds: 0, endSeconds: 2)
            ],
            title: "테스트",
            languageHint: "ko"
        )
        #expect(result.contains("요약"))
        #expect(result.contains("핵심 결정 3건"))
    }

    @Test func summarizerHandlesHTTP500() async {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse("{\"error\":\"server\"}", status: 500, url: url)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let s = OpenAISummarizer(apiKey: "sk-fake", endpoint: url, session: session)
        do {
            _ = try await s.summarize(
                utterances: [Utterance(speaker: Speaker(id: "A"), text: "x", startSeconds: 0, endSeconds: 1)],
                title: nil, languageHint: "ko"
            )
            Issue.record("Expected HTTP error")
        } catch let e as SummarizationError {
            if case .http(let status, _) = e {
                #expect(status == 500)
            } else { Issue.record("Unexpected: \(e)") }
        } catch { Issue.record("Unexpected: \(error)") }
    }

    // MARK: - OpenAI Translator

    @Test func translatorEndToEndParsesNumberedResponse() async throws {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(
                "{\"choices\":[{\"message\":{\"content\":\"1. Hello\\n2. World\\n3. Foo\"}}]}",
                url: url
            )
        }
        defer { MockURLProtocol.requestHandler = nil }
        let t = OpenAITranslator(apiKey: "sk-fake", endpoint: url, session: session)
        let translated = try await t.translate(texts: ["안녕", "세계", "푸"], targetLang: "en")
        #expect(translated == ["Hello", "World", "Foo"])
    }

    @Test func translatorFallsBackToRawLineWhenNumberingMissing() async throws {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse(
                "{\"choices\":[{\"message\":{\"content\":\"Hello\\nWorld\"}}]}",
                url: url
            )
        }
        defer { MockURLProtocol.requestHandler = nil }
        let t = OpenAITranslator(apiKey: "sk-fake", endpoint: url, session: session)
        let translated = try await t.translate(texts: ["안녕", "세계"], targetLang: "en")
        #expect(translated == ["Hello", "World"])
    }

    // MARK: - OpenAI AskAI

    @Test func askAIEndToEndIncludesHistoryInRequest() async throws {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        let session = MockURLProtocol.makeSession()
        let observed = ObservableHolder<[[String: Any]]>()
        MockURLProtocol.requestHandler = { req in
            let body = extractBody(req)
            if let dict = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
               let messages = dict["messages"] as? [[String: Any]] {
                observed.value = messages
            }
            return MockURLProtocol.jsonResponse(
                "{\"choices\":[{\"message\":{\"content\":\"답변입니다.\"}}]}",
                url: url
            )
        }
        defer { MockURLProtocol.requestHandler = nil }

        let svc = OpenAIAskAI(apiKey: "sk-fake", endpoint: url, session: session)
        let answer = try await svc.ask(
            utterances: [Utterance(speaker: Speaker(id: "A"), text: "hi", startSeconds: 0, endSeconds: 1)],
            history: [
                AskAIMessage(role: .user, content: "이전 질문"),
                AskAIMessage(role: .assistant, content: "이전 답변"),
            ],
            question: "두 번째 질문",
            languageHint: "ko"
        )
        #expect(answer == "답변입니다.")
        let messages = observed.value ?? []
        #expect(messages.count == 4)
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.last?["role"] as? String == "user")
        #expect(messages.last?["content"] as? String == "두 번째 질문")
    }

    // MARK: - Notion

    @Test func notionEndToEndReturnsPageURL() async throws {
        let url = URL(string: "https://example.com/v1/pages")!
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { req in
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer secret_x")
            #expect(req.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")
            return MockURLProtocol.jsonResponse(
                "{\"url\":\"https://www.notion.so/test-abc123\"}",
                url: url
            )
        }
        defer { MockURLProtocol.requestHandler = nil }
        let exporter = NotionAPIExporter(integrationToken: "secret_x", endpoint: url, session: session)
        let pageURL = try await exporter.exportMeeting(
            title: "테스트",
            body: MeetingExportData(title: "테스트", durationSeconds: 60, utterances: []),
            databaseID: "db",
            parentPageID: nil
        )
        #expect(pageURL.absoluteString.contains("notion.so"))
    }

    @Test func notionEndToEndDecodingFailsOnMissingURL() async {
        let url = URL(string: "https://example.com/v1/pages")!
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.jsonResponse("{\"object\":\"page\"}", url: url)
        }
        defer { MockURLProtocol.requestHandler = nil }
        let exporter = NotionAPIExporter(integrationToken: "secret_x", endpoint: url, session: session)
        do {
            _ = try await exporter.exportMeeting(
                title: "t",
                body: MeetingExportData(title: "t", durationSeconds: 0, utterances: []),
                databaseID: "db", parentPageID: nil
            )
            Issue.record("Expected decoding error")
        } catch let e as NotionExportError {
            if case .decoding = e { /* pass */ }
            else { Issue.record("Unexpected: \(e)") }
        } catch { Issue.record("Unexpected: \(error)") }
    }
}

// MARK: - Holder

private final class ObservableHolder<T>: @unchecked Sendable {
    var value: T?
}
