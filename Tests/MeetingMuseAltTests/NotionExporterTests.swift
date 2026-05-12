import Testing
import Foundation
@testable import MeetingMuseAlt

private func sampleData() -> MeetingExportData {
    MeetingExportData(
        title: "테스트 회의",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 120,
        language: "ko",
        summary: "핵심 결정 3건.",
        utterances: [
            Utterance(speaker: Speaker(id: "A", label: "Alice"), text: "안녕", startSeconds: 0, endSeconds: 2),
            Utterance(speaker: Speaker(id: "B", label: "Bob"),   text: "Hi",  startSeconds: 65, endSeconds: 67),
        ]
    )
}

@Test func notionRejectsEmptyToken() async {
    let exporter = NotionAPIExporter(integrationToken: "")
    do {
        _ = try await exporter.exportMeeting(title: "t", body: sampleData(), databaseID: "db", parentPageID: nil)
        Issue.record("missingCredentials expected")
    } catch let e as NotionExportError {
        if case .missingCredentials = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func notionRejectsMissingParent() async {
    let exporter = NotionAPIExporter(integrationToken: "secret_x")
    do {
        _ = try await exporter.exportMeeting(title: "t", body: sampleData(), databaseID: nil, parentPageID: nil)
        Issue.record("missingParent expected")
    } catch let e as NotionExportError {
        if case .missingParent = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func payloadIncludesTitleAndChildren() {
    let payload = NotionAPIExporter.buildPayload(
        title: "테스트 회의",
        body: sampleData(),
        databaseID: "abc-123",
        parentPageID: nil
    )
    #expect((payload["parent"] as? [String: Any])?["database_id"] as? String == "abc-123")
    let children = payload["children"] as? [[String: Any]] ?? []
    #expect(children.count >= 3) // 메타 + 요약 헤더 + 요약 + 전사 헤더 + 전사 N개
    let firstParaText = (((children.first?["paragraph"] as? [String: Any])?["rich_text"] as? [[String: Any]])?.first?["text"] as? [String: Any])?["content"] as? String
    #expect(firstParaText?.contains("회의록") == true)
}

@Test func payloadPagePidPathUsesPageID() {
    let payload = NotionAPIExporter.buildPayload(
        title: "t",
        body: sampleData(),
        databaseID: nil,
        parentPageID: "page-xyz"
    )
    #expect((payload["parent"] as? [String: Any])?["page_id"] as? String == "page-xyz")
    #expect((payload["parent"] as? [String: Any])?["database_id"] == nil)
}
