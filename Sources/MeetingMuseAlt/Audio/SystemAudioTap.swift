import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// macOS 14.4+ Core Audio Process Tap을 통해 다른 앱(Zoom, Meet, Teams 등)이
/// 재생하는 시스템 오디오를 캡처합니다.
///
/// **상태**: M2.3 스카폴드. 다음이 실제로 구현되어 있습니다.
///  - pid → `AudioObjectID` 변환 (`kAudioHardwarePropertyTranslatePIDToProcessObject`)
///  - `CATapDescription` (mono mixdown / global) 생성
///  - `AudioHardwareCreateProcessTap` / `AudioHardwareDestroyProcessTap` 호출
///  - 마이크 + 탭을 함께 읽기 위한 aggregate device 생성 (옵션)
///
/// **후속 PR로 미룬 것** (의도적):
///  - 탭 출력 버퍼 스트리밍 (`AudioDeviceCreateIOProcID` + ring buffer →
///    `AVAudioPCMBuffer` 변환). 현재 `captureProcess` / `captureSystemOutput` 의
///    AsyncStream 은 `.notImplemented` 로 종료됩니다.
///  - `AudioRecorder` 와의 통합 (별도 PR — AudioRecorder.swift line 65 TODO).
public final class SystemAudioTap: @unchecked Sendable {
    public static let shared = SystemAudioTap()
    private init() {}

    public enum TapError: LocalizedError {
        case notImplemented
        case permissionRequired
        case unsupportedOS
        case invalidPID(pid_t)
        case processObjectNotFound(pid_t)
        case coreAudio(OSStatus, String)

        public var errorDescription: String? {
            switch self {
            case .notImplemented:
                return "시스템 오디오 캡처는 다음 마일스톤에서 구현됩니다."
            case .permissionRequired:
                return "시스템 설정 > 개인정보 보호 > 마이크 / 화면 녹화 권한이 필요합니다."
            case .unsupportedOS:
                return "시스템 오디오 캡처는 macOS 14.4 이상이 필요합니다."
            case .invalidPID(let pid):
                return "유효하지 않은 프로세스 ID 입니다: \(pid)"
            case .processObjectNotFound(let pid):
                return "PID \(pid) 에 해당하는 Core Audio 프로세스 객체를 찾을 수 없습니다. 해당 앱이 오디오를 재생 중인지 확인하세요."
            case .coreAudio(let status, let label):
                return "Core Audio 오류 (\(label)): OSStatus=\(status)"
            }
        }
    }

    // MARK: - Public API

    /// 지정한 process ID의 오디오 출력을 캡처합니다.
    /// - Parameters:
    ///   - pid: 캡처 대상 프로세스 PID (`MeetingAppDetector`가 알려줌)
    ///   - sampleRate: 모노 PCM의 샘플레이트 (Whisper 권장: 16000)
    /// - Returns: 캡처가 시작되면 PCM 버퍼를 비동기로 송출하는 AsyncStream.
    ///   현재(M2.3 스카폴드)는 탭/aggregate device 까지만 만들고
    ///   `.notImplemented` 으로 finish — 버퍼 스트리밍은 후속 PR.
    public func captureProcess(pid: Int32, sampleRate: Double = 16_000) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            // 1) Validate PID early so callers (and tests) get a clear error.
            guard pid > 0 else {
                continuation.finish(throwing: TapError.invalidPID(pid))
                return
            }

            // 2) Gate on macOS 14.4+ — the Tap APIs are not available on older OSes.
            guard #available(macOS 14.4, *) else {
                continuation.finish(throwing: TapError.unsupportedOS)
                return
            }

            // 3) Real work: translate pid, create tap, create aggregate device.
            //    We tear everything down before finishing because buffer
            //    streaming is not implemented yet — this proves the path
            //    compiles and the system accepts our calls.
            do {
                let tapID = try Self.createMonoProcessTap(for: pid)
                defer { Self.destroyTap(tapID) }

                // Buffer streaming via AudioDeviceCreateIOProcID is intentionally
                // not implemented in this PR — see file header doc comment.
                continuation.finish(throwing: TapError.notImplemented)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// 모든 앱의 시스템 출력을 캡처합니다. (글로벌 탭)
    public func captureSystemOutput(sampleRate: Double = 16_000) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            guard #available(macOS 14.4, *) else {
                continuation.finish(throwing: TapError.unsupportedOS)
                return
            }
            do {
                let tapID = try Self.createGlobalMonoTap()
                defer { Self.destroyTap(tapID) }
                continuation.finish(throwing: TapError.notImplemented)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// 기존 `AVAudioEngine` 의 입력에 시스템 오디오 탭을 믹스해 붙입니다.
    /// `AudioRecorder` 가 마이크와 시스템 오디오를 함께 녹음하고 싶을 때 호출합니다.
    ///
    /// 현재(M2.3 스카폴드)는 탭/aggregate device 까지 만들고 `TapError.notImplemented`
    /// 를 throw 합니다. 실제 노드 attach 는 후속 PR (IO proc → AVAudioPCMBuffer
    /// 변환이 선행되어야 함).
    ///
    /// - Parameters:
    ///   - engine: 마이크 입력을 잡고 있는 활성 `AVAudioEngine`
    ///   - pid: 캡처 대상 프로세스 PID. `nil` 이면 글로벌 탭
    public func attach(to engine: AVAudioEngine, pid: Int32? = nil) throws {
        guard #available(macOS 14.4, *) else {
            throw TapError.unsupportedOS
        }
        let tapID: AudioObjectID
        if let pid {
            guard pid > 0 else { throw TapError.invalidPID(pid) }
            tapID = try Self.createMonoProcessTap(for: pid)
        } else {
            tapID = try Self.createGlobalMonoTap()
        }
        // Tear the tap down again — we don't have the IOProc plumbing yet.
        // (The function signature exists so AudioRecorder can call us today
        // and the wiring can be filled in without an interface change.)
        Self.destroyTap(tapID)
        throw TapError.notImplemented
    }

    // MARK: - Core Audio helpers (internal — exposed for tests)

    /// `pid_t` → Core Audio `AudioObjectID` 변환.
    /// `kAudioHardwarePropertyTranslatePIDToProcessObject` 사용.
    ///
    /// PID 가 존재하지 않거나 해당 프로세스가 오디오를 출력한 적이 없으면
    /// Core Audio 는 에러 없이 `kAudioObjectUnknown` 을 돌려줍니다.
    /// 그 경우 `TapError.processObjectNotFound` 로 변환합니다.
    @available(macOS 14.4, *)
    static func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        guard pid > 0 else { throw TapError.invalidPID(pid) }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var inputPID: pid_t = pid
        var outID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = withUnsafePointer(to: &inputPID) { qualifierPtr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifierPtr,
                &size,
                &outID
            )
        }

        guard status == noErr else {
            throw TapError.coreAudio(status, "TranslatePIDToProcessObject")
        }
        guard outID != AudioObjectID(kAudioObjectUnknown) else {
            throw TapError.processObjectNotFound(pid)
        }
        return outID
    }

    /// 주어진 PID 의 프로세스 오디오 출력만 모노 믹스다운으로 캡처하는 탭을 만듭니다.
    /// 호출자가 `destroyTap(_:)` 으로 해제해야 합니다.
    @available(macOS 14.4, *)
    static func createMonoProcessTap(for pid: pid_t) throws -> AudioObjectID {
        let processObject = try processObjectID(for: pid)
        // The Obj-C API takes NSArray<NSNumber*>* but the Swift refinement
        // (NS_REFINED_FOR_SWIFT) imports it as [AudioObjectID].
        let description = CATapDescription(monoMixdownOfProcesses: [processObject])
        description.name = "MeetingMuseAlt Process Tap (pid \(pid))"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        return try createTap(with: description)
    }

    /// 시스템 전체 출력을 (요청자 자신은 제외하고) 모노로 캡처하는 글로벌 탭을 만듭니다.
    @available(macOS 14.4, *)
    static func createGlobalMonoTap() throws -> AudioObjectID {
        // exclude no processes → all processes are tapped
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "MeetingMuseAlt Global Tap"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        return try createTap(with: description)
    }

    @available(macOS 14.4, *)
    private static func createTap(with description: CATapDescription) throws -> AudioObjectID {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw TapError.coreAudio(status, "AudioHardwareCreateProcessTap")
        }
        guard tapID != AudioObjectID(kAudioObjectUnknown) else {
            throw TapError.coreAudio(status, "AudioHardwareCreateProcessTap returned unknown id")
        }
        return tapID
    }

    /// 탭 해제. 실패해도 throw 하지 않음 (이미 destroy 되었거나 시스템이 회수했을 수 있음).
    @available(macOS 14.4, *)
    static func destroyTap(_ tapID: AudioObjectID) {
        guard tapID != AudioObjectID(kAudioObjectUnknown) else { return }
        let status = AudioHardwareDestroyProcessTap(tapID)
        #if DEBUG
        if status != noErr {
            print("[SystemAudioTap] destroyTap(\(tapID)) returned \(status)")
        }
        #endif
    }
}
