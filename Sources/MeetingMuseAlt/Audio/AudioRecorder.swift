import Foundation
import AVFoundation

public struct AudioRecording: Sendable {
    public let fileURL: URL
    public let durationSeconds: Double
}

public enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case microphoneDenied
    case sessionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "이미 녹음 중입니다."
        case .notRecording: return "녹음이 시작되지 않았습니다."
        case .microphoneDenied: return "마이크 권한이 거부되었습니다. 시스템 설정에서 허용해주세요."
        case .sessionFailed(let m): return "오디오 세션 실패: \(m)"
        }
    }
}

/// AVFoundation 기반 마이크 녹음 + 라이브 오디오 스트림.
///
/// 라이브 오디오는 `AsyncStream<AVAudioPCMBuffer>` 형태로 노출하며,
/// 추후 `WhisperEngine`이 이 버퍼를 chunk 단위로 소비해서 실시간 전사 결과를 만든다.
public final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private var startTime: Date?

    private var liveContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    public private(set) lazy var liveAudioStream: AsyncStream<AVAudioPCMBuffer> = {
        AsyncStream { continuation in
            self.liveContinuation = continuation
        }
    }()

    public init() {}

    public func start(includeSystemAudio: Bool) async throws {
        guard !engine.isRunning else { throw AudioRecorderError.alreadyRecording }

        try await ensureMicPermission()

        let format = engine.inputNode.outputFormat(forBus: 0)
        let url = makeOutputURL()
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }
        fileURL = url

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            self.liveContinuation?.yield(buffer)
        }

        if includeSystemAudio {
            // TODO(M2): Wire SystemAudioTap.shared.attach(to: engine) once Core Audio tap PoC lands.
            // For now we record only the input device.
            #if DEBUG
            print("[AudioRecorder] System audio capture requested — falls back to mic-only until M2.")
            #endif
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }
        startTime = Date()
    }

    public func stop() async throws -> AudioRecording {
        guard engine.isRunning, let url = fileURL else {
            throw AudioRecorderError.notRecording
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        liveContinuation?.finish()
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        audioFile = nil
        fileURL = nil
        startTime = nil
        return AudioRecording(fileURL: url, durationSeconds: duration)
    }

    // MARK: - Helpers

    private func makeOutputURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDir = dir.appendingPathComponent("MeetingMuseAlt", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return appDir.appendingPathComponent("recording-\(stamp).caf")
    }

    private func ensureMicPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw AudioRecorderError.microphoneDenied }
        case .denied, .restricted:
            throw AudioRecorderError.microphoneDenied
        @unknown default:
            throw AudioRecorderError.microphoneDenied
        }
    }
}
