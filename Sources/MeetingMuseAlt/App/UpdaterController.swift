import SwiftUI
import Sparkle

/// Sparkle 자동 업데이트 컨트롤러 래퍼.
///
/// `appcast.xml` URL 은 `Info.plist` 의 `SUFeedURL` 키 또는
/// `EnvironmentValues` 로 주입한다. 기본값은 GitHub Releases 위에 호스팅하는
/// raw appcast.xml — `project.yml` 에 적힘.
///
/// 사용자는 메뉴바 → "업데이트 확인..." (`checkForUpdates()`) 클릭으로 즉시
/// 폴링을 트리거할 수 있고, 백그라운드 자동 폴링도 동작한다 (`SUAutomaticallyUpdate`
/// + `SUScheduledCheckInterval`).
@MainActor
public final class UpdaterController: ObservableObject {
    public static let shared = UpdaterController()

    /// 업데이트 사용 가능 여부 (메뉴 항목 enable 게이팅용)
    @Published public private(set) var canCheckForUpdates: Bool = false

    private let updaterController: SPUStandardUpdaterController

    public init() {
        // startingUpdater: true 로 즉시 백그라운드 폴링 시작.
        // userDriver: SPUStandardUserDriver — 표준 다이얼로그 UI 자동 사용.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    /// 메뉴 → "업데이트 확인..." 액션.
    public func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    /// 현재 설치된 버전 (Info.plist CFBundleShortVersionString).
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Sparkle feed URL — `Info.plist` 의 `SUFeedURL` 키에서 읽힘.
    public var feedURL: String {
        Bundle.main.infoDictionary?["SUFeedURL"] as? String ?? ""
    }
}

/// SwiftUI 커맨드 메뉴 — `MeetingMuseAltApp.body` 의 `.commands` 에 추가.
public struct UpdaterCommands: Commands {
    @ObservedObject var controller: UpdaterController

    public init(controller: UpdaterController) {
        self.controller = controller
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("업데이트 확인...") {
                controller.checkForUpdates()
            }
            .disabled(!controller.canCheckForUpdates)
        }
    }
}
