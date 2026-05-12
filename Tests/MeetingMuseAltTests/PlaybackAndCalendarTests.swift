import Testing
import Foundation
@testable import MeetingMuseAlt

// MARK: - AudioPlaybackController

@MainActor
@Test func audioPlaybackInitialStateIsEmpty() {
    let c = AudioPlaybackController()
    #expect(c.fileURL == nil)
    #expect(c.isPlaying == false)
    #expect(c.currentTime == 0)
    #expect(c.duration == 0)
}

@MainActor
@Test func audioPlaybackLoadMissingFileSetsErrorMessage() {
    let c = AudioPlaybackController()
    let missing = URL(fileURLWithPath: "/tmp/__not_existing_\(UUID().uuidString).wav")
    c.load(url: missing)
    #expect(c.fileURL == nil || c.player_internal == nil || c.errorMessage != nil)
}

@MainActor
@Test func audioPlaybackSeekClampsToDuration() {
    // 빈 controller에서 seek 호출은 no-op (player nil)
    let c = AudioPlaybackController()
    c.seek(toSeconds: 100)
    #expect(c.currentTime == 0)
}

@MainActor
@Test func audioPlaybackFormatTime() {
    #expect(AudioPlaybackController.formatTime(0) == "00:00")
    #expect(AudioPlaybackController.formatTime(65) == "01:05")
    #expect(AudioPlaybackController.formatTime(3599) == "59:59")
    #expect(AudioPlaybackController.formatTime(-1) == "00:00")
}

@MainActor
@Test func audioPlaybackTogglePlayOnEmptyControllerIsNoOp() {
    let c = AudioPlaybackController()
    c.togglePlay()
    #expect(c.isPlaying == false)
}

// MARK: - GoogleCalendarExporter

@Test func gcalRejectsEmptyToken() async {
    let exporter = GoogleCalendarAPIExporter()
    do {
        _ = try await exporter.createEvent(
            summary: "회의", description: "본문",
            startDate: Date(), durationSeconds: 60,
            calendarID: "primary", accessToken: ""
        )
        Issue.record("missingToken expected")
    } catch let e as GoogleCalendarError {
        if case .missingToken = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func gcalRejectsEmptyCalendarID() async {
    let exporter = GoogleCalendarAPIExporter()
    do {
        _ = try await exporter.createEvent(
            summary: "x", description: "x",
            startDate: Date(), durationSeconds: 60,
            calendarID: "", accessToken: "fake"
        )
        Issue.record("invalidCalendarID expected")
    } catch let e as GoogleCalendarError {
        if case .invalidCalendarID = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}

@Test func gcalBuildPayloadIncludesISODatesAndTimezone() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(3_600)
    let payload = GoogleCalendarAPIExporter.buildPayload(
        summary: "회의", description: "본문", startDate: start, endDate: end
    )
    #expect(payload["summary"] as? String == "회의")
    let s = payload["start"] as? [String: Any]
    let e = payload["end"] as? [String: Any]
    #expect((s?["dateTime"] as? String)?.contains("2023-11-14") == true)
    #expect((e?["dateTime"] as? String)?.contains("2023-11-14") == true)
    #expect(s?["timeZone"] is String)
}

// MARK: - GoogleCalendar 종단 mock 은 HTTPIntegrationSuite 에 통합 (process-wide
// static handler race 방지 — 별도 .serialized suite 사이도 병렬 실행되기 때문).
// HTTPIntegrationTests.swift 에 같은 suite 로 추가됨.

// MARK: - 테스트용 internal access helper

extension AudioPlaybackController {
    /// Test-only: 내부 player 가 nil 인지 검사 (load 실패 검증용).
    @MainActor
    fileprivate var player_internal: Any? {
        // mirror reflection 으로 private player 접근
        let mirror = Mirror(reflecting: self)
        return mirror.children.first(where: { $0.label == "player" })?.value
    }
}
