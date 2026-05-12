import Foundation
import AVFoundation
import Combine

/// 회의 녹음 재생 컨트롤러.
///
/// `AVAudioPlayer` 를 감싸고 `@Published currentTime` 으로 1초 간격 위치를 노출.
/// SwiftUI 뷰가 이 controller 를 observe 해서 발화 하이라이트 / 진행 바 표시.
/// `seek(toSeconds:)` 으로 발화 클릭 → 점프.
@MainActor
public final class AudioPlaybackController: ObservableObject {
    @Published public private(set) var fileURL: URL?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    public init() {}

    /// 새 오디오 파일 로드. 이전 재생은 정지.
    public func load(url: URL) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            self.player = p
            self.fileURL = url
            self.duration = p.duration
            self.currentTime = 0
            self.errorMessage = nil
        } catch {
            self.player = nil
            self.fileURL = nil
            self.duration = 0
            self.errorMessage = "오디오 로드 실패: \(error.localizedDescription)"
        }
    }

    public func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        if let player { currentTime = player.currentTime }
    }

    public func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    public func seek(toSeconds seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, player.duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    public func unload() {
        stop()
        player = nil
        fileURL = nil
        duration = 0
        currentTime = 0
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                // 끝까지 재생되면 자동 정지
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    public static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
