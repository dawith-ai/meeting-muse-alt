import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func menuBarStatusTitleIdle() {
    #expect(MenuBarStatus.statusTitle(isRecording: false, elapsed: 0) == "Meeting Muse Alt")
    // elapsed is ignored when not recording
    #expect(MenuBarStatus.statusTitle(isRecording: false, elapsed: 9999) == "Meeting Muse Alt")
}

@Test func menuBarStatusTitleRecordingFormatsAsMMSS() {
    #expect(MenuBarStatus.statusTitle(isRecording: true, elapsed: 65) == "녹음 중 — 01:05")
    #expect(MenuBarStatus.statusTitle(isRecording: true, elapsed: 0) == "녹음 중 — 00:00")
    #expect(MenuBarStatus.statusTitle(isRecording: true, elapsed: 3599) == "녹음 중 — 59:59")
}

@Test func menuBarIconNameSwitchesOnRecording() {
    #expect(MenuBarStatus.iconName(isRecording: false) == "waveform")
    #expect(MenuBarStatus.iconName(isRecording: true) == "record.circle.fill")
}
