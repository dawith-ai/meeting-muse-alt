import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// macOS 14.4+ Core Audio Process Tap을 통해 다른 앱(Zoom, Meet, Teams 등)이
/// 재생하는 시스템 오디오를 캡처합니다.
///
/// **상태 (M2.3 완료)**:
///  - pid → `AudioObjectID` 변환 (`kAudioHardwarePropertyTranslatePIDToProcessObject`)
///  - `CATapDescription` (mono mixdown / global) 생성
///  - `AudioHardwareCreateProcessTap` / `AudioHardwareDestroyProcessTap` 호출
///  - `AudioHardwareCreateAggregateDevice` + `kAudioAggregateDeviceTapListKey`
///    로 탭을 sub-device 로 포함하는 aggregate device 생성/해제
///  - `AudioDeviceCreateIOProcIDWithBlock` 으로 IO proc 등록 → AudioBufferList 를
///    `AVAudioPCMBuffer` 로 변환 → `AsyncThrowingStream` 으로 yield
///
/// **운영 제약**:
///  - macOS 14.4+ 필요. 미만 OS 에서는 `.unsupportedOS` throw.
///  - "Screen & System Audio Recording" 권한이 필요 (TCC 다이얼로그가 첫
///    실행 시 자동 표시됨). 권한 없으면 IOProc 콜백이 호출되지 않는다.
///  - Process Tap 은 대상 프로세스가 활성 오디오를 출력 중일 때만 데이터를 흘려준다.
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
        case formatNegotiationFailed

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
            case .formatNegotiationFailed:
                return "Core Audio 탭의 native 포맷을 얻을 수 없습니다."
            }
        }
    }

    // MARK: - Public API

    /// 지정한 process ID 의 오디오 출력을 캡처합니다.
    public func captureProcess(pid: Int32, sampleRate: Double = 16_000) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            guard pid > 0 else {
                continuation.finish(throwing: TapError.invalidPID(pid))
                return
            }
            guard #available(macOS 14.4, *) else {
                continuation.finish(throwing: TapError.unsupportedOS)
                return
            }
            do {
                let session = try TapSession.start(scope: .process(pid: pid), continuation: continuation)
                continuation.onTermination = { _ in session.stop() }
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
                let session = try TapSession.start(scope: .global, continuation: continuation)
                continuation.onTermination = { _ in session.stop() }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// 기존 `AVAudioEngine` 에 시스템 오디오 캡처를 시작하고, 그 PCM 을 엔진의
    /// player node 에 스케줄링해 mixer 와 함께 mixing 합니다.
    ///
    /// 반환된 `AttachedSession` 을 `stop()` 호출로 정리해야 합니다.
    /// `attach` 가 던지면 호출자(`AudioRecorder.start`)는 catch 하여 마이크 only
    /// 모드로 폴백하면 됩니다.
    @discardableResult
    public func attach(to engine: AVAudioEngine, pid: Int32? = nil) throws -> AttachedSession {
        guard #available(macOS 14.4, *) else {
            throw TapError.unsupportedOS
        }
        let scope: TapScope
        if let pid {
            guard pid > 0 else { throw TapError.invalidPID(pid) }
            scope = .process(pid: pid)
        } else {
            scope = .global
        }
        return try AttachedSession.start(engine: engine, scope: scope)
    }

    /// `attach(to:pid:)` 의 반환 타입.
    /// 외부에서는 `stop()` 호출만 가능하며 내부는 `TapSession` + `AVAudioPlayerNode`.
    public final class AttachedSession: @unchecked Sendable {
        fileprivate let stopHandler: () -> Void
        fileprivate init(stopHandler: @escaping () -> Void) {
            self.stopHandler = stopHandler
        }
        public func stop() { stopHandler() }
        deinit { stopHandler() }

        @available(macOS 14.4, *)
        fileprivate static func start(engine: AVAudioEngine, scope: TapScope) throws -> AttachedSession {
            let stream = AsyncThrowingStream<AVAudioPCMBuffer, Error> { continuation in
                do {
                    let session = try TapSession.start(scope: scope, continuation: continuation)
                    continuation.onTermination = { _ in session.stop() }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // 별도 player node 를 엔진에 붙이고, tap 의 PCM 을 schedule.
            let player = AVAudioPlayerNode()
            engine.attach(player)

            // Player 의 format 은 첫 buffer 에서 결정 — 미리 main mixer 에 임시 연결.
            // SystemAudioTap 의 native format 은 보통 32-bit float mono 16-48kHz.
            // 첫 buffer 가 들어올 때까지 연결을 미루고, 들어오면 연결 + play.
            var connected = false
            let consumeTask = Task.detached {
                do {
                    for try await buf in stream {
                        if Task.isCancelled { break }
                        if !connected {
                            await MainActor.run {
                                if engine.isRunning {
                                    engine.connect(player, to: engine.mainMixerNode, format: buf.format)
                                } else {
                                    engine.connect(player, to: engine.mainMixerNode, format: buf.format)
                                }
                                player.play()
                            }
                            connected = true
                        }
                        await player.scheduleBuffer(buf)
                    }
                } catch {
                    #if DEBUG
                    print("[SystemAudioTap.attach] stream ended with error: \(error)")
                    #endif
                }
            }

            let stop: () -> Void = {
                consumeTask.cancel()
                player.stop()
                engine.detach(player)
            }
            return AttachedSession(stopHandler: stop)
        }
    }

    // MARK: - Core Audio helpers (internal — exposed for tests)

    /// `pid_t` → Core Audio `AudioObjectID` 변환.
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

    @available(macOS 14.4, *)
    static func createMonoProcessTap(for pid: pid_t) throws -> AudioObjectID {
        let processObject = try processObjectID(for: pid)
        let description = CATapDescription(monoMixdownOfProcesses: [processObject])
        description.name = "MeetingMuseAlt Process Tap (pid \(pid))"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        return try createTap(with: description)
    }

    @available(macOS 14.4, *)
    static func createGlobalMonoTap() throws -> AudioObjectID {
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

// MARK: - TapScope

@available(macOS 14.4, *)
fileprivate enum TapScope {
    case process(pid: pid_t)
    case global

    var label: String {
        switch self {
        case .process(let pid): return "process-\(pid)"
        case .global: return "global"
        }
    }
}

// MARK: - TapSession (lifecycle owner — tap + aggregate device + IO proc)

@available(macOS 14.4, *)
fileprivate final class TapSession: @unchecked Sendable {
    let tapID: AudioObjectID
    let aggregateID: AudioObjectID
    let ioProcID: AudioDeviceIOProcID
    let continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation
    private let queue: DispatchQueue
    private var isStopped = false
    private let stopLock = NSLock()

    /// Tap 의 실제 출력 포맷 (보통 32-bit float, native sample rate, mono).
    let inputFormat: AVAudioFormat

    static func start(
        scope: TapScope,
        continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation
    ) throws -> TapSession {
        // 1) 탭 생성
        let tapID: AudioObjectID
        switch scope {
        case .process(let pid):
            tapID = try SystemAudioTap.createMonoProcessTap(for: pid)
        case .global:
            tapID = try SystemAudioTap.createGlobalMonoTap()
        }

        // 2) tap 의 native stream format 조회
        let format: AVAudioFormat
        do {
            format = try Self.readTapFormat(tapID: tapID)
        } catch {
            SystemAudioTap.destroyTap(tapID)
            throw error
        }

        // 3) Aggregate device 생성 (tap 을 sub-device 로 등록)
        let aggregateID: AudioObjectID
        do {
            aggregateID = try Self.createAggregateDevice(includingTap: tapID, label: scope.label)
        } catch {
            SystemAudioTap.destroyTap(tapID)
            throw error
        }

        // 4) IO proc 등록 — 콜백 안에서 AudioBufferList → AVAudioPCMBuffer 변환 후 yield
        let queue = DispatchQueue(label: "kr.dawith.meetingmuse.alt.tap-io.\(scope.label)")
        var ioProcID: AudioDeviceIOProcID?
        let session: TapSession

        // 큐/포맷/continuation 을 weak 캡처하는 박싱
        final class Box: @unchecked Sendable {
            weak var session: TapSession?
        }
        let box = Box()

        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateID,
            queue
        ) { (_: UnsafePointer<AudioTimeStamp>,
             inInputData: UnsafePointer<AudioBufferList>,
             _: UnsafePointer<AudioTimeStamp>,
             _: UnsafeMutablePointer<AudioBufferList>,
             _: UnsafePointer<AudioTimeStamp>) in
            box.session?.handleInput(inInputData: inInputData)
        }
        guard status == noErr, let ioProcID else {
            Self.destroyAggregateDevice(aggregateID)
            SystemAudioTap.destroyTap(tapID)
            throw SystemAudioTap.TapError.coreAudio(status, "AudioDeviceCreateIOProcIDWithBlock")
        }

        session = TapSession(
            tapID: tapID,
            aggregateID: aggregateID,
            ioProcID: ioProcID,
            inputFormat: format,
            queue: queue,
            continuation: continuation
        )
        box.session = session

        // 5) IO 시작
        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        guard startStatus == noErr else {
            session.stop()
            throw SystemAudioTap.TapError.coreAudio(startStatus, "AudioDeviceStart")
        }
        return session
    }

    private init(
        tapID: AudioObjectID,
        aggregateID: AudioObjectID,
        ioProcID: AudioDeviceIOProcID,
        inputFormat: AVAudioFormat,
        queue: DispatchQueue,
        continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation
    ) {
        self.tapID = tapID
        self.aggregateID = aggregateID
        self.ioProcID = ioProcID
        self.inputFormat = inputFormat
        self.queue = queue
        self.continuation = continuation
    }

    func handleInput(inInputData: UnsafePointer<AudioBufferList>) {
        let ablList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard let firstBuffer = ablList.first,
              let mData = firstBuffer.mData
        else { return }
        let bytesPerFrame = inputFormat.streamDescription.pointee.mBytesPerFrame
        guard bytesPerFrame > 0 else { return }
        let frameCount = AVAudioFrameCount(firstBuffer.mDataByteSize / bytesPerFrame)
        guard frameCount > 0 else { return }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else { return }
        pcm.frameLength = frameCount
        let byteCount = Int(firstBuffer.mDataByteSize)
        if let dst = pcm.floatChannelData?[0] {
            // tap 은 보통 32-bit float interleaved mono — bytesPerFrame == 4
            UnsafeMutableRawPointer(dst).copyMemory(from: mData, byteCount: byteCount)
        } else if let dst = pcm.int16ChannelData?[0] {
            UnsafeMutableRawPointer(dst).copyMemory(from: mData, byteCount: byteCount)
        }
        continuation.yield(pcm)
    }

    func stop() {
        stopLock.lock()
        defer { stopLock.unlock() }
        guard !isStopped else { return }
        isStopped = true
        _ = AudioDeviceStop(aggregateID, ioProcID)
        _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        Self.destroyAggregateDevice(aggregateID)
        SystemAudioTap.destroyTap(tapID)
    }

    deinit {
        stop()
    }

    // MARK: - Helpers

    private static func readTapFormat(tapID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            throw SystemAudioTap.TapError.coreAudio(status, "kAudioTapPropertyFormat")
        }
        guard let fmt = AVAudioFormat(streamDescription: &asbd) else {
            throw SystemAudioTap.TapError.formatNegotiationFailed
        }
        return fmt
    }

    private static func createAggregateDevice(
        includingTap tapID: AudioObjectID,
        label: String
    ) throws -> AudioObjectID {
        // tap UID 를 알아낸다 — kAudioTapPropertyUID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let uidStatus = withUnsafeMutablePointer(to: &cfStr) { ptr in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, ptr)
        }
        guard uidStatus == noErr, let tapUID = cfStr as String? else {
            throw SystemAudioTap.TapError.coreAudio(uidStatus, "kAudioTapPropertyUID")
        }

        let aggregateUID = "kr.dawith.meetingmuse.alt.aggregate.\(label).\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "MeetingMuseAlt Aggregate (\(label))",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceIsStackedKey as String: 0,
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapUIDKey as String: tapUID,
                kAudioSubTapDriftCompensationKey as String: 0,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            throw SystemAudioTap.TapError.coreAudio(status, "AudioHardwareCreateAggregateDevice")
        }
        guard aggregateID != AudioObjectID(kAudioObjectUnknown) else {
            throw SystemAudioTap.TapError.coreAudio(status, "AudioHardwareCreateAggregateDevice returned unknown id")
        }
        return aggregateID
    }

    fileprivate static func destroyAggregateDevice(_ aggregateID: AudioObjectID) {
        guard aggregateID != AudioObjectID(kAudioObjectUnknown) else { return }
        let status = AudioHardwareDestroyAggregateDevice(aggregateID)
        #if DEBUG
        if status != noErr {
            print("[SystemAudioTap] destroyAggregateDevice(\(aggregateID)) returned \(status)")
        }
        #endif
    }
}
