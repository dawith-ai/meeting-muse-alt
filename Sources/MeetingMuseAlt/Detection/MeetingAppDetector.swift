import Foundation
import AppKit
import Combine

public struct DetectedMeetingApp: Hashable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let processIdentifier: Int32
}

/// 실행 중인 회의 앱(Zoom, Google Meet 브라우저 탭, Teams 등)을 감지합니다.
///
/// 1초마다 `NSWorkspace.shared.runningApplications`를 폴링해서
/// 화이트리스트와 매칭되는 앱이 활성화되면 `detectedApps`에 추가합니다.
@MainActor
public final class MeetingAppDetector: ObservableObject {
    @Published public private(set) var detectedApps: [DetectedMeetingApp] = []

    private var timer: Timer?

    /// Bundle ID → 사용자 표시명 화이트리스트.
    /// 새 회의 앱을 추가하려면 여기에 항목만 추가하면 됩니다.
    nonisolated public static let bundleWhitelist: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.cisco.webex.meetings": "Webex",
        "com.google.Chrome": "Chrome (Google Meet 가능)",
        "com.google.Chrome.canary": "Chrome Canary",
        "com.apple.Safari": "Safari (Google Meet 가능)",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Edge",
        "com.tinyspeck.slackmacgap": "Slack (Huddle 가능)",
        "com.hnc.Discord": "Discord"
    ]

    public init() {}

    public func start() {
        stop()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let running = NSWorkspace.shared.runningApplications
        let detected: [DetectedMeetingApp] = running.compactMap { app in
            guard
                let bundle = app.bundleIdentifier,
                let displayName = Self.bundleWhitelist[bundle]
            else { return nil }
            return DetectedMeetingApp(
                bundleIdentifier: bundle,
                displayName: displayName,
                processIdentifier: app.processIdentifier
            )
        }
        // Stable sort & dedupe by bundle id
        var seen = Set<String>()
        let dedup = detected.filter { seen.insert($0.bundleIdentifier).inserted }
        if dedup != detectedApps {
            detectedApps = dedup
        }
    }
}
