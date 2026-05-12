import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func appleSummarizerRejectsEmptyUtterancesEvenIfAvailable() async {
    let s = AppleFoundationSummarizer()
    do {
        _ = try await s.summarize(utterances: [], title: nil, languageHint: "ko")
        Issue.record("emptyUtterances expected")
    } catch let e as SummarizationError {
        if case .emptyUtterances = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch { Issue.record("Unexpected: \(error)") }
}

@Test func appleAskAIRejectsEmptyQuestion() async {
    let s = AppleFoundationAskAI()
    do {
        _ = try await s.ask(
            utterances: [], history: [], question: "   ", languageHint: "ko"
        )
        Issue.record("emptyQuestion expected")
    } catch let e as AskAIError {
        if case .emptyQuestion = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch { Issue.record("Unexpected: \(error)") }
}

@Test func appleTranslatorRejectsEmptyInput() async {
    let t = AppleFoundationTranslator()
    do {
        _ = try await t.translate(texts: [], targetLang: "en")
        Issue.record("emptyInput expected")
    } catch let e as TranslationError {
        if case .emptyInput = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch { Issue.record("Unexpected: \(error)") }
}

@Test func availabilityIsBooleanReadable() {
    // 환경에 따라 true / false 가지만 호출 자체가 던지지 않으면 OK.
    let _ = AppleFoundationModels.isAvailable
    let _ = AppleFoundationModels.unavailabilityReason
    #expect(true)
}

@Test func appleTranslatorRejectsUnsupportedLanguageWhenAvailable() async {
    // 환경이 available 이라도 unsupportedLanguage 가 우선 (texts non-empty 시).
    // 미가용 환경에서는 notImplemented 가 먼저 — 그것도 OK.
    let t = AppleFoundationTranslator()
    do {
        _ = try await t.translate(texts: ["hi"], targetLang: "xx")
        Issue.record("error expected")
    } catch let e as TranslationError {
        switch e {
        case .unsupportedLanguage(let lang): #expect(lang == "xx")
        case .notImplemented: /* 환경 미가용 — OK */ break
        default: Issue.record("Unexpected: \(e)")
        }
    } catch { Issue.record("Unexpected: \(error)") }
}
