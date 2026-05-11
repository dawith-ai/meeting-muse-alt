import SwiftUI
import AppKit

/// Pure helpers for the menu bar status item.
///
/// `MenuBarExtra` is a SwiftUI scene and is not easily unit-testable,
/// so we keep the small bits of presentation logic here as `static` funcs
/// and cover them with tests.
public enum MenuBarStatus {
    /// Status item / menu header title.
    ///
    /// - Idle: `"Meeting Muse Alt"`
    /// - Recording: `"녹음 중 — MM:SS"` (e.g. 65s → `"녹음 중 — 01:05"`)
    public static func statusTitle(isRecording: Bool, elapsed: TimeInterval) -> String {
        guard isRecording else {
            return "Meeting Muse Alt"
        }
        let total = max(0, Int(elapsed))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "녹음 중 — %02d:%02d", minutes, seconds)
    }

    /// SF Symbol name for the status item icon.
    public static func iconName(isRecording: Bool) -> String {
        isRecording ? "record.circle.fill" : "waveform"
    }
}

/// Content view rendered inside `MenuBarExtra`.
///
/// Mirrors recording state and exposes quick actions:
/// 녹음 시작/정지, 메인 창 열기, 자동 감지된 회의 앱 서브메뉴, 종료.
struct MenuBarScene: View {
    @EnvironmentObject private var vm: RecordingViewModel
    @EnvironmentObject private var detector: MeetingAppDetector

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Header — mirrors recording state
        Text(MenuBarStatus.statusTitle(isRecording: vm.isRecording, elapsed: vm.elapsedSeconds))

        Divider()

        // Toggle record
        Button(vm.isRecording ? "녹음 정지" : "녹음 시작") {
            Task { await vm.toggleRecording() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("메인 창 열기") {
            openMainWindow()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Divider()

        // Auto-detected meeting apps submenu
        Menu("회의 앱 자동 감지") {
            if detector.detectedApps.isEmpty {
                Text("실행 중인 회의 앱 없음")
            } else {
                ForEach(detector.detectedApps, id: \.bundleIdentifier) { app in
                    Text(app.displayName)
                }
            }
        }

        Divider()

        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Try the SwiftUI WindowGroup default first.
        // (Falls back silently if no window with that id is registered — the
        // main WindowGroup is the default scene and AppKit activation above
        // already brings it forward in most cases.)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
