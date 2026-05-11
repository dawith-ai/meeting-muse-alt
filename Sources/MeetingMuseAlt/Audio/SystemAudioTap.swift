import Foundation
import AVFoundation

/// macOS 14.4+ Core Audio Process Tap을 통해 다른 앱(Zoom, Meet, Teams 등)이
/// 재생하는 시스템 오디오를 캡처합니다.
///
/// **상태**: M2 마일스톤. 현재는 인터페이스만 정의되어 있으며,
/// 실제 캡처는 `CATapDescription` + `AudioHardwareCreateProcessTap`을 사용해
/// 구현해야 합니다. ROADMAP.md M2 참조.
public final class SystemAudioTap: @unchecked Sendable {
    public static let shared = SystemAudioTap()
    private init() {}

    public enum TapError: LocalizedError {
        case notImplemented
        case permissionRequired
        case unsupportedOS

        public var errorDescription: String? {
            switch self {
            case .notImplemented:
                return "시스템 오디오 캡처는 다음 마일스톤에서 구현됩니다."
            case .permissionRequired:
                return "시스템 설정 > 개인정보 보호 > 마이크 / 화면 녹화 권한이 필요합니다."
            case .unsupportedOS:
                return "시스템 오디오 캡처는 macOS 14.4 이상이 필요합니다."
            }
        }
    }

    /// 지정한 process ID의 오디오 출력을 캡처합니다.
    /// - Parameters:
    ///   - pid: 캡처 대상 프로세스 PID (`MeetingAppDetector`가 알려줌)
    ///   - sampleRate: 모노 PCM의 샘플레이트 (Whisper 권장: 16000)
    /// - Returns: 캡처가 시작되면 PCM 버퍼를 비동기로 송출하는 AsyncStream
    public func captureProcess(pid: Int32, sampleRate: Double = 16_000) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            // TODO(M2): AudioHardwareCreateProcessTap + AudioObjectAddPropertyListener
            continuation.finish(throwing: TapError.notImplemented)
        }
    }

    /// 모든 앱의 시스템 출력을 캡처합니다. (글로벌 탭)
    public func captureSystemOutput(sampleRate: Double = 16_000) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            // TODO(M2): Aggregate tap across the default output device
            continuation.finish(throwing: TapError.notImplemented)
        }
    }
}
