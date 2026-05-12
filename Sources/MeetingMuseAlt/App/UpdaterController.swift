import SwiftUI

/// 개인용 빌드 — 자동 업데이트는 비활성.
/// 업데이트는 `git pull && ./scripts/install.sh` 로 수동 진행.
///
/// 공개 배포가 필요해지면 Sparkle 의존성 + SPUStandardUpdaterController 로
/// 복원. DEPLOYMENT.md 부록의 release.yml 워크플로우 참조.
@MainActor
public final class UpdaterController: ObservableObject {
    public static let shared = UpdaterController()
    @Published public private(set) var canCheckForUpdates: Bool = false
    public init() {}
    public func checkForUpdates() {}
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

/// 빈 커맨드 — 메뉴에 항목 추가하지 않음 (Sparkle 없으므로).
public struct UpdaterCommands: Commands {
    @ObservedObject var controller: UpdaterController
    public init(controller: UpdaterController) {
        self.controller = controller
    }
    public var body: some Commands {
        CommandGroup(after: .appInfo) { EmptyView() }
    }
}
