import Foundation
import AVFoundation

public enum WhisperEngineError: LocalizedError {
    case modelMissing
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Whisper 모델이 설치되지 않았습니다. README의 '모델 설치' 절차를 따라주세요."
        case .decodingFailed(let m):
            return "전사 디코딩 실패: \(m)"
        }
    }
}

/// Whisper.cpp + CoreML 인코더 기반 전사 엔진.
///
/// **현재 상태 (M2.1)**: 모델 경로 조회/설치는 `ModelInstaller` 로 위임되었고,
/// 실제 whisper.cpp FFI 호출은 아직 연결되지 않았습니다.
/// 다음 마일스톤(M2.2+) 에서 다음 단계를 통해 활성화됩니다:
///   1. Package.swift에 `whisper.cpp` SPM 의존성 추가 (cSettings/linkerSettings + CoreML.framework 필요)
///   2. Application Support/MeetingMuseAlt/Models 에 `ggml-base.bin` + `ggml-base-encoder.mlmodelc` 배치
///   3. `WhisperContext` 가 `whisper_init_from_file_with_params` 를 호출하도록 구현
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
    /// 모델 weights/CoreML 인코더가 위치한 디렉터리. `nil`이면 `ModelInstaller.defaultModelDirectory()`.
    public let modelDirectory: URL?

    public init(mode: Mode = .stub, modelName: String = "base") {
        self.mode = mode
        self.modelName = modelName
        self.modelDirectory = nil
    }

    /// 테스트/CLI에서 모델 디렉터리를 주입하기 위한 오버로드.
    public init(mode: Mode = .stub, modelName: String = "base", modelDirectory: URL?) {
        self.mode = mode
        self.modelName = modelName
        self.modelDirectory = modelDirectory
    }

    // MARK: - File transcription

    public func transcribe(audioURL: URL) async throws -> [Utterance] {
        switch resolvedMode() {
        case .stub:
            return await Self.stubUtterances(for: audioURL)
        case .real:
            // M2.2+: WhisperContext 가 ggml weights + CoreML encoder 를 로드하고
            // PCM 16k mono float32 데이터를 `whisper_full` 에 넘긴 뒤 segment 를 Utterance 로 매핑.
            // 현재는 계약을 명확히 노출하기 위해 명시적 에러를 던집니다.
            throw WhisperEngineError.decodingFailed("whisper.cpp FFI not yet wired")
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
            return Self.modelBundled(named: modelName, in: modelDirectory) ? .real : .stub
        }
    }

    private static func modelBundled(named name: String, in directory: URL?) -> Bool {
        return ModelInstaller.isModelInstalled(name: name, in: directory)
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

    // MARK: - FFI bridge
    //
    // whisper.cpp 의 C API (`whisper_context *`, `whisper_full_params`, `whisper_full`,
    // `whisper_full_n_segments`, `whisper_full_get_segment_text` 등) 를 Swift 에서
    // 호출하기 위한 자리 표시(placeholder) 입니다.
    //
    // SPM 의존성이 추가되면 이 타입이 다음을 책임집니다:
    //   - init(modelPath:, coreMLEncoderPath:)  → whisper_init_from_file_with_params
    //   - transcribe(samples:)                  → whisper_full + segment 반복
    //   - deinit                                → whisper_free
    //
    // 현재는 빌드를 깨지 않도록 빈 struct 로 둡니다. 외부에 노출하지 않습니다.
    private struct WhisperContext {
        let modelPath: URL
        let coreMLEncoderPath: URL?

        // TODO(M2.2): UnsafeMutablePointer<whisper_context> 보관 + whisper_free in deinit.
    }
}
