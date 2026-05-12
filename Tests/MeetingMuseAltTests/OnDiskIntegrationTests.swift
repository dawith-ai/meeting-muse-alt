import Testing
import Foundation
@testable import MeetingMuseAlt

/// 실제 파일에 쓰고 새 인스턴스로 다시 로드해서 라운드트립을 검증.
/// 모든 테스트는 임시 디렉토리를 만들고 끝나면 정리.

private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mmalt-integ-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - MeetingExporter 실 파일 쓰기

@Test func meetingExporterWritesHTMLAndPlainTextToDisk() throws {
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }

    let exporter = MeetingExporter()
    let data = MeetingExportData(
        title: "통합 테스트 회의",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 120,
        language: "ko",
        summary: "결정 사항 2건.",
        utterances: [
            Utterance(speaker: Speaker(id: "A", label: "Alice"), text: "안녕하세요", startSeconds: 0, endSeconds: 3),
            Utterance(speaker: Speaker(id: "B", label: "Bob"),   text: "반갑습니다", startSeconds: 3, endSeconds: 6),
        ]
    )

    let html = tmp.appendingPathComponent("meeting.html")
    let txt = tmp.appendingPathComponent("meeting.txt")
    let md = tmp.appendingPathComponent("meeting.md")

    try exporter.write(data, to: html, as: .html)
    try exporter.write(data, to: txt, as: .plainText)
    try exporter.write(data, to: md, as: .markdown)

    let htmlStr = try String(contentsOf: html, encoding: .utf8)
    let txtStr = try String(contentsOf: txt, encoding: .utf8)
    let mdStr = try String(contentsOf: md, encoding: .utf8)

    #expect(htmlStr.contains("<!DOCTYPE html>"))
    #expect(htmlStr.contains("통합 테스트 회의"))
    #expect(htmlStr.contains("Alice"))
    #expect(htmlStr.contains("결정 사항 2건."))

    #expect(txtStr.contains("[00:00] Alice: 안녕하세요"))
    #expect(!txtStr.contains("<"))

    #expect(mdStr.hasPrefix("# 통합 테스트 회의"))
    #expect(mdStr.contains("**00:00**"))
    #expect(mdStr.contains("## 요약"))
}

// MARK: - MeetingPersistence 실 파일 라운드트립

@MainActor
@Test func meetingPersistenceRealFileRoundTrip() throws {
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }
    let storeURL = tmp.appendingPathComponent("meetings.json")

    // 첫 인스턴스: 디스크에 쓴다
    let p1 = ManualPersistence(storeURL: storeURL)
    try p1.save(MeetingRecord(
        title: "온디스크 회의 1",
        durationSeconds: 100,
        utterances: [
            Utterance(speaker: Speaker(id: "A", label: "Alice"), text: "한국어", startSeconds: 0, endSeconds: 2),
        ]
    ))
    try p1.save(MeetingRecord(
        title: "온디스크 회의 2",
        durationSeconds: 200,
        utterances: []
    ))

    // 디스크에 실제 JSON 파일이 생겼는지
    #expect(FileManager.default.fileExists(atPath: storeURL.path))
    let raw = try Data(contentsOf: storeURL)
    #expect(raw.count > 0)
    let str = String(data: raw, encoding: .utf8) ?? ""
    #expect(str.contains("온디스크 회의 1"))
    #expect(str.contains("Alice"))

    // 새 인스턴스로 로드해서 동일한 데이터가 보이는지
    let p2 = ManualPersistence(storeURL: storeURL)
    let loaded = p2.all()
    #expect(loaded.count == 2)
    #expect(loaded.contains { $0.title == "온디스크 회의 1" })
    let withUtts = loaded.first { $0.title == "온디스크 회의 1" }!
    #expect(withUtts.utterances.count == 1)
    #expect(withUtts.utterances[0].text == "한국어")
}

/// `MeetingPersistence` 의 `defaultStoreURL` 우회용 — 임의 storeURL 로
/// 동일 JSON 인코딩/로드 동작을 직접 수행. (실제 `MeetingPersistence` 는
/// `shared` 가 `Application Support` 경로에 묶여 있어 테스트 디렉토리로
/// 외부 주입할 수 없으므로 동일 로직을 인라인 재현.)
@MainActor
private final class ManualPersistence {
    let storeURL: URL
    var records: [MeetingRecord] = []
    init(storeURL: URL) {
        self.storeURL = storeURL
        if FileManager.default.fileExists(atPath: storeURL.path),
           let data = try? Data(contentsOf: storeURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = (try? decoder.decode([MeetingRecord].self, from: data)) ?? []
        }
    }
    func save(_ rec: MeetingRecord) throws {
        records.append(rec)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(records)
        try data.write(to: storeURL, options: [.atomic])
    }
    func all() -> [MeetingRecord] { records }
}

// MARK: - PyannoteEngine 모델 미설치 → 명확한 에러

@Test func pyannoteSegmentThrowsModelMissing() async throws {
    let tmp = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tmp) }

    let engine = PyannoteEngine(modelDirectory: tmp)
    #expect(engine.isModelInstalled == false)
    do {
        _ = try await engine.segment(audioURL: URL(fileURLWithPath: "/dev/null"))
        Issue.record("Expected modelMissing")
    } catch let e as PyannoteEngineError {
        if case .modelMissing = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

// MARK: - ActionItemExtractor 가 OpenAISummarizer 출력 형태와 호환

@Test func actionExtractorParsesRealisticSummarizerOutput() {
    // OpenAISummarizer 의 시스템 프롬프트가 만드는 전형적인 마크다운 모양
    let summary = """
    ## 핵심 요약
    분기 매출 검토와 마케팅 전략 정렬 회의.

    ## 주요 논의 사항
    - 인스타그램 리엘스 비중 확대
    - 백엔드 일정 재조정

    ## 결정 사항
    - 리엘스 예산 30% 증액
    - 코드 동결 1주 연장

    ## 액션 아이템 (담당자/기한)
    - 리엘스 캠페인 기획 (담당: 김유나, 기한: 2026-05-20, 우선순위: 높음)
    - 백엔드 일정 업데이트 (담당: 홍길동, 기한: 2026-05-25)
    - 마케팅 보고서 공유 (담당: 박재희)
    """
    let items = ActionItemExtractor.extract(from: summary)
    #expect(items.count == 3)
    #expect(items[0].task == "리엘스 캠페인 기획")
    #expect(items[0].assignee == "김유나")
    #expect(items[0].priority == .high)
    #expect(items[1].dueText == "2026-05-25")
    #expect(items[2].assignee == "박재희")
}

// MARK: - MeetingSearchEngine 가 큰 데이터셋 일관성

@Test func searchEngineHandlesLargeCollection() {
    var records: [MeetingRecord] = []
    for i in 0..<50 {
        let utts = (0..<10).map { j in
            Utterance(
                speaker: Speaker(id: j.isMultiple(of: 2) ? "A" : "B"),
                text: "회의 \(i) 발화 \(j) 키워드\(j % 3)",
                startSeconds: Double(j),
                endSeconds: Double(j + 1)
            )
        }
        records.append(MeetingRecord(
            title: "회의 \(i)",
            createdAt: Date(timeIntervalSince1970: Double(1_700_000_000 + i)),
            durationSeconds: 10,
            utterances: utts
        ))
    }
    let engine = MeetingSearchEngine()
    let hits = engine.search(records, query: MeetingSearchQuery(text: "키워드1"))
    #expect(hits.count == 50)
    // 모든 회의에 키워드1 발화가 정확히 3-4개 있어야 함 (j%3==1 인 j: 1,4,7 → 3개)
    for hit in hits {
        #expect(hit.utteranceHits.count == 3)
    }
    // 화자 필터
    let onlyA = engine.search(records, query: MeetingSearchQuery(text: "키워드", speakerID: "A"))
    for hit in onlyA {
        #expect(hit.utteranceHits.allSatisfy { $0.utterance.speaker.id == "A" })
    }
}

// MARK: - MenuBarStatus 가 60초 이상 시간 포맷 (회귀)

@Test func menuBarStatusHandlesLongDuration() {
    #expect(MenuBarStatus.statusTitle(isRecording: true, elapsed: 7325) == "녹음 중 — 122:05")
    // (현재 구현은 분:초 2자리만, 시간 단위 분리 안 함 — 의도된 단순화)
}
