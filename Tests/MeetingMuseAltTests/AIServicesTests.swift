import Testing
import Foundation
@testable import MeetingMuseAlt

// MARK: - OpenAISummarizer

@Test func summarizerRejectsMissingAPIKey() async {
    let s = OpenAISummarizer(apiKey: "")
    let result: Result<String, Error>
    do {
        let out = try await s.summarize(
            utterances: [Utterance(speaker: Speaker(id: "A"), text: "hi", startSeconds: 0, endSeconds: 1)],
            title: nil,
            languageHint: "ko"
        )
        result = .success(out)
    } catch {
        result = .failure(error)
    }
    switch result {
    case .failure(let e as SummarizationError):
        if case .missingAPIKey = e { /* pass */ }
        else { Issue.record("Unexpected error: \(e)") }
    default:
        Issue.record("Expected missingAPIKey error")
    }
}

@Test func summarizerRejectsEmptyUtterances() async {
    let s = OpenAISummarizer(apiKey: "sk-fake")
    do {
        _ = try await s.summarize(utterances: [], title: nil, languageHint: "ko")
        Issue.record("Expected emptyUtterances error")
    } catch let e as SummarizationError {
        if case .emptyUtterances = e { /* pass */ }
        else { Issue.record("Unexpected error: \(e)") }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func summarizerFormatsTranscriptWithTimestampsAndSpeakers() {
    let utts = [
        Utterance(speaker: Speaker(id: "A", label: "Alice"), text: "안녕", startSeconds: 0, endSeconds: 2),
        Utterance(speaker: Speaker(id: "B", label: "Bob"),   text: "Hello", startSeconds: 65, endSeconds: 67),
    ]
    let out = OpenAISummarizer.formatTranscript(utts)
    #expect(out.contains("[00:00] Alice: 안녕"))
    #expect(out.contains("[01:05] Bob: Hello"))
}

@Test func summarizerRequestBodyIsValidJSONWithModel() throws {
    let data = OpenAISummarizer.makeRequestBody(
        model: "gpt-4o-mini",
        transcript: "[00:00] A: hi",
        title: "테스트 회의",
        languageHint: "ko"
    )
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["model"] as? String == "gpt-4o-mini")
    let messages = json?["messages"] as? [[String: Any]]
    #expect(messages?.count == 2)
    let userContent = messages?.last?["content"] as? String
    #expect(userContent?.contains("테스트 회의") == true)
}

@Test func summarizerExtractsTextFromValidResponse() throws {
    let payload = """
    {"choices":[{"message":{"content":"## 핵심 요약\\n- A 발화"}}]}
    """.data(using: .utf8)!
    let text = try OpenAISummarizer.extractText(from: payload)
    #expect(text.contains("핵심 요약"))
}

@Test func localLlamaSummarizerThrowsNotImplemented() async {
    let s = LocalLlamaSummarizer()
    do {
        _ = try await s.summarize(utterances: [], title: nil, languageHint: "ko")
        Issue.record("Expected notImplemented")
    } catch let e as SummarizationError {
        if case .notImplemented = e { /* pass */ }
        else { Issue.record("Unexpected error: \(e)") }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

// MARK: - OpenAITranslator

@Test func translatorRejectsEmptyTexts() async {
    let t = OpenAITranslator(apiKey: "sk-fake")
    do {
        _ = try await t.translate(texts: [], targetLang: "en")
        Issue.record("Expected emptyInput")
    } catch let e as TranslationError {
        if case .emptyInput = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func translatorRejectsUnsupportedLanguage() async {
    let t = OpenAITranslator(apiKey: "sk-fake")
    do {
        _ = try await t.translate(texts: ["hi"], targetLang: "xx")
        Issue.record("Expected unsupportedLanguage")
    } catch let e as TranslationError {
        if case .unsupportedLanguage(let lang) = e {
            #expect(lang == "xx")
        } else {
            Issue.record("Unexpected: \(e)")
        }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func translatorRejectsMissingAPIKey() async {
    let t = OpenAITranslator(apiKey: "")
    do {
        _ = try await t.translate(texts: ["hi"], targetLang: "ko")
        Issue.record("Expected missingAPIKey")
    } catch let e as TranslationError {
        if case .missingAPIKey = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func translatorRejectsTooManyTexts() async {
    let t = OpenAITranslator(apiKey: "sk-fake")
    let texts = Array(repeating: "hi", count: 100)
    do {
        _ = try await t.translate(texts: texts, targetLang: "en")
        Issue.record("Expected tooManyTexts")
    } catch let e as TranslationError {
        if case .tooManyTexts(let limit) = e {
            #expect(limit == OpenAITranslator.maxTexts)
        } else {
            Issue.record("Unexpected: \(e)")
        }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func translatorParsesNumberedLinesInOrder() {
    let raw = """
    1. Hello
    2. World
    3. Foo
    """
    let parsed = OpenAITranslator.parseNumberedLines(raw: raw, expectedCount: 3)
    #expect(parsed == ["Hello", "World", "Foo"])
}

@Test func translatorParseFallbackOnMissingNumbers() {
    let raw = "no numbers here\nsecond line"
    let parsed = OpenAITranslator.parseNumberedLines(raw: raw, expectedCount: 2)
    #expect(parsed[0] == "no numbers here")
    #expect(parsed[1] == "second line")
}

@Test func translatorParseHandlesPartialNumbering() {
    let raw = """
    1. First
    skipped line
    3. Third
    """
    let parsed = OpenAITranslator.parseNumberedLines(raw: raw, expectedCount: 3)
    #expect(parsed[0] == "First")
    #expect(parsed[2] == "Third")
    // index 1 falls back to the raw line at offset 1
    #expect(parsed[1] == "skipped line")
}

@Test func translatorSupportedLanguagesContainsExpected() {
    let langs = OpenAITranslator.supportedLanguages
    #expect(langs.keys.contains("en"))
    #expect(langs.keys.contains("ko"))
    #expect(langs.keys.contains("vi"))
}

@Test func localNLLBTranslatorThrowsNotImplemented() async {
    let t = LocalNLLBTranslator()
    do {
        _ = try await t.translate(texts: ["hi"], targetLang: "en")
        Issue.record("Expected notImplemented")
    } catch let e as TranslationError {
        if case .notImplemented = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}
