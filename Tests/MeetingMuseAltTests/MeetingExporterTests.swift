import Testing
import Foundation
@testable import MeetingMuseAlt

private func sampleData(
    title: String = "샘플 회의",
    summary: String? = nil,
    utterances: [Utterance] = [
        Utterance(
            speaker: Speaker(id: "A", label: "발화자 A"),
            text: "안녕하세요.",
            startSeconds: 0,
            endSeconds: 3
        ),
        Utterance(
            speaker: Speaker(id: "B", label: "발화자 B"),
            text: "반갑습니다.",
            startSeconds: 3,
            endSeconds: 6
        ),
    ]
) -> MeetingExportData {
    MeetingExportData(
        title: title,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 6,
        language: "ko",
        summary: summary,
        utterances: utterances
    )
}

@Test func htmlContainsEscapedTitleAndStyleBlock() {
    let exporter = MeetingExporter()
    let out = exporter.render(sampleData(title: "Q&A <Session>"), as: .html)
    #expect(out.contains("<!DOCTYPE html>"))
    #expect(out.contains("<style>"))
    #expect(out.contains("Q&amp;A &lt;Session&gt;"))
    // raw HTML version of the title must NOT appear
    #expect(!out.contains("Q&A <Session>"))
}

@Test func htmlEscapesScriptInjectionInTitleAndText() {
    let evil = "<script>alert(\"x\")</script>"
    let exporter = MeetingExporter()
    let data = sampleData(
        title: evil,
        utterances: [
            Utterance(
                speaker: Speaker(id: "X", label: evil),
                text: evil,
                startSeconds: 0,
                endSeconds: 1
            )
        ]
    )
    let out = exporter.render(data, as: .html)
    #expect(!out.contains("<script>"))
    #expect(out.contains("&lt;script&gt;"))
    #expect(out.contains("&quot;"))
}

@Test func markdownStartsWithH1AndUsesBoldTimestamps() {
    let exporter = MeetingExporter()
    let md = exporter.render(sampleData(), as: .markdown)
    #expect(md.hasPrefix("# 샘플 회의"))
    #expect(md.contains("**00:00**"))
    #expect(md.contains("**00:03**"))
}

@Test func plainTextHasNoHtmlTags() {
    let exporter = MeetingExporter()
    let txt = exporter.render(sampleData(), as: .plainText)
    #expect(!txt.contains("<"))
    #expect(!txt.contains(">"))
    #expect(txt.contains("[00:00]"))
    #expect(txt.contains("발화자 A"))
}

@Test func writeToTempFileProducesReadableUTF8() throws {
    let exporter = MeetingExporter()
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let url = dir.appendingPathComponent("export-\(UUID().uuidString).html")
    defer { try? FileManager.default.removeItem(at: url) }

    try exporter.write(sampleData(), to: url, as: .html)
    let read = try String(contentsOf: url, encoding: .utf8)
    #expect(!read.isEmpty)
    #expect(read.contains("<!DOCTYPE html>"))
    #expect(read.contains("샘플 회의"))
}

@Test func speakerColorIsDeterministic() {
    let a1 = MeetingExporter.speakerColorHSL(speakerID: "speaker-A")
    let a2 = MeetingExporter.speakerColorHSL(speakerID: "speaker-A")
    let b = MeetingExporter.speakerColorHSL(speakerID: "speaker-B")
    #expect(a1 == a2)
    #expect(a1.hasPrefix("hsl("))
    // different speakers SHOULD produce different colors (extremely high
    // probability with a 360-hue space and FNV-1a)
    #expect(a1 != b)
}

@Test func emptyUtterancesProducesValidHTML() {
    let exporter = MeetingExporter()
    let data = MeetingExportData(
        title: "빈 회의",
        durationSeconds: 0,
        utterances: []
    )
    let out = exporter.render(data, as: .html)
    #expect(out.contains("<!DOCTYPE html>"))
    #expect(out.contains("빈 회의"))
    #expect(out.contains("발화 없음"))
}

@Test func summaryRendersWhenNonNil() {
    let exporter = MeetingExporter()
    let html = exporter.render(sampleData(summary: "핵심 결정 3건."), as: .html)
    #expect(html.contains("핵심 결정 3건."))
    #expect(html.contains("class=\"summary\""))

    let md = exporter.render(sampleData(summary: "핵심 결정 3건."), as: .markdown)
    #expect(md.contains("## 요약"))
    #expect(md.contains("핵심 결정 3건."))
}

@Test func htmlEscapeHandlesAllReservedCharacters() {
    #expect(MeetingExporter.htmlEscape("&") == "&amp;")
    #expect(MeetingExporter.htmlEscape("<") == "&lt;")
    #expect(MeetingExporter.htmlEscape(">") == "&gt;")
    #expect(MeetingExporter.htmlEscape("\"") == "&quot;")
    #expect(MeetingExporter.htmlEscape("'") == "&#39;")
    #expect(MeetingExporter.htmlEscape("safe") == "safe")
}

@Test func durationFormatHandlesHoursAndZero() {
    #expect(MeetingExporter.formatDuration(0) == "00:00")
    #expect(MeetingExporter.formatDuration(65) == "01:05")
    #expect(MeetingExporter.formatDuration(3_725) == "1:02:05")
}
