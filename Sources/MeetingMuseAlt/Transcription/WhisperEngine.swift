import Foundation
import AVFoundation

public enum WhisperEngineError: LocalizedError {
    case modelMissing
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Whisper 모델이 번들에 포함되지 않았습니다. README의 '모델 설치' 절차를 따라주세요."
        case .decodingFailed(let m):
            return "전사 디코딩 실패: \(m)"
        }
    }
}

/// Whisper.cpp + CoreML 인코더 기반 전사 엔진.
///
/// **현재 상태 (M1)**: Whisper.cpp Swift 바인딩이 추가되기 전까지 stub.
/// 실제 동작은 다음 마일스톤에서 다음 단계를 통해 활성화됩니다:
///   1. Package.swift에 `whisper.cpp` SPM 의존성 추가
///   2. Resources/Models/에 `ggml-base.bin` + `ggml-base-encoder.mlmodelc` 배치
///   3. `transcribe(audioURL:)`에서 `whisper_init_from_file_with_params` 호출
///
/// stub 모드에서는 더미 utterance를 반환해 UI 흐름을 검증할 수 있습니다.
public final class WhisperEngine: TranscriptionService {
    public enum Mode: Sendable {
        /// 실제 Whisper 모델 사용. 모델이 없으면 자동으로 `.stub` 로 폴백.
        case real
        /// UI 시연용 더미 결과 반환.
        case stub
    }

    public let mode: Mode
    public let modelName: String

    public init(mode: Mode = .stub, modelName: String = "ggml-base") {
        self.mode = mode
        self.modelName = modelName
    }

    // MARK: - File transcription

    public func transcribe(audioURL: URL) async throws -> [Utterance] {
        switch resolvedMode() {
        case .stub:
            return await Self.stubUtterances(for: audioURL)
        case .real:
            // TODO(M2): whisper.cpp Swift bridge
            return await Self.stubUtterances(for: audioURL)
        }
    }

    // MARK: - Live transcription

    public func liveTranscriptionStream(from input: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                var accumulated: Double = 0
                var counter = 0
                for await _ in input {
                    if Task.isCancelled { break }
                    // M1 stub: emit a placeholder utterance every ~3 seconds of buffered audio.
                    accumulated += 0.1
                    if accumulated >= 3.0 {
                        accumulated = 0
                        counter += 1
                        let utt = Utterance(
                            speaker: Speaker(id: "A", label: "발화자 A"),
                            text: "(라이브 전사 #\(counter) — Whisper 통합 시 실제 텍스트로 대체됩니다.)",
                            startSeconds: Double(counter) * 3,
                            endSeconds: Double(counter + 1) * 3
                        )
                        continuation.yield(utt)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func resolvedMode() -> Mode {
        switch mode {
        case .stub: return .stub
        case .real:
            return Self.modelBundled(named: modelName) ? .real : .stub
        }
    }

    private static func modelBundled(named name: String) -> Bool {
        // M2: lookup in Bundle.module.url(forResource: name, withExtension: "bin")
        return false
    }

    private static func stubUtterances(for audioURL: URL) async -> [Utterance] {
        let asset = AVURLAsset(url: audioURL)
        let durationSeconds: Double
        do {
            let dur = try await asset.load(.duration)
            durationSeconds = CMTimeGetSeconds(dur)
        } catch {
            durationSeconds = 0
        }
        let safeDuration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 10
        let speakerA = Speaker(id: "A", label: "발화자 A")
        let speakerB = Speaker(id: "B", label: "발화자 B")
        return [
            Utterance(
                speaker: speakerA,
                text: "(데모 전사) 실제 Whisper 모델이 연결되면 이 자리에 발화 내용이 들어갑니다.",
                startSeconds: 0,
                endSeconds: min(4, safeDuration)
            ),
            Utterance(
                speaker: speakerB,
                text: "(데모 전사) Pyannote 화자분리 모델을 통해 다른 화자로 구분된 결과입니다.",
                startSeconds: min(4, safeDuration),
                endSeconds: safeDuration
            )
        ]
    }
}
