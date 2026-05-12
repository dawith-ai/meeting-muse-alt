import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func askAIRejectsMissingAPIKey() async {
    let s = OpenAIAskAI(apiKey: "")
    do {
        _ = try await s.ask(
            utterances: [Utterance(speaker: Speaker(id: "A"), text: "hi", startSeconds: 0, endSeconds: 1)],
            history: [],
            question: "무엇?",
            languageHint: "ko"
        )
        Issue.record("missingAPIKey expected")
    } catch let e as AskAIError {
        if case .missingAPIKey = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func askAIRejectsEmptyQuestion() async {
    let s = OpenAIAskAI(apiKey: "sk-fake")
    do {
        _ = try await s.ask(utterances: [], history: [], question: "   ", languageHint: "ko")
        Issue.record("emptyQuestion expected")
    } catch let e as AskAIError {
        if case .emptyQuestion = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func askAIFormatsTranscriptWithTimestamps() {
    let utts = [
        Utterance(speaker: Speaker(id: "A", label: "Alice"), text: "안녕", startSeconds: 0, endSeconds: 2),
        Utterance(speaker: Speaker(id: "B", label: "Bob"), text: "Hi", startSeconds: 65, endSeconds: 67),
    ]
    let out = OpenAIAskAI.formatTranscript(utts)
    #expect(out.contains("[00:00] Alice: 안녕"))
    #expect(out.contains("[01:05] Bob: Hi"))
}

@Test func askAIMessageRoleRawValues() {
    #expect(AskAIMessage.Role.user.rawValue == "user")
    #expect(AskAIMessage.Role.assistant.rawValue == "assistant")
}
