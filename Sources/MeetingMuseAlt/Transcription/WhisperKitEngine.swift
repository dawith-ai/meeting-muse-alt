import Foundation
import AVFoundation
import WhisperKit

/// `WhisperKit` (argmaxinc) 을 통해 실제 whisper.cpp + CoreML 추론을 수행하는 엔진.
///
/// 첫 호출 시점에 모델이 자동 다운로드된다 (Hugging Face cache).
/// 모델이 없거나 초기화 실패 시 `WhisperEngine`(stub) 로 폴백할 수 있도록
/// `transcribe` 가 던지는 에러를 호출자가 처리하면 된다.
public final class WhisperKitEngine: TranscriptionService, @unchecked Sendable {
    /// WhisperKit 모델 이름. 기본값은 가장 가벼운 `tiny` (~75MB).
    public private(set) var modelName: String

    /// 런타임에 모델을 교체. 이미 로드된 파이프는 폐기되어 다음 호출 시 재초기화.
    public func setModelName(_ newName: String) async {
        guard newName != modelName else { return }
        modelName = newName
        await box.reset()
    }
    /// 초기화는 actor 격리로 단일 호출만 발생하도록 보장한다.
    private actor PipeBox {
        var pipe: WhisperKit?
        func setIfNil(_ new: WhisperKit) -> WhisperKit {
            if let existing = pipe { return existing }
            pipe = new
            return new
        }
        func current() -> WhisperKit? { pipe }
        func reset() { pipe = nil }
    }
    private let box = PipeBox()

    public init(modelName: String = "tiny") {
        self.modelName = modelName
    }

    // MARK: - TranscriptionService

    public func transcribe(audioURL: URL) async throws -> [Utterance] {
        let pipe = try await ensurePipe()
        let results = try await pipe.transcribe(audioPath: audioURL.path)
        return Self.convertToUtterances(results)
    }

    /// 라이브 전사: 30s 윈도우/5s hop 으로 누적 버퍼를 주기적으로 전사한다.
    ///
    /// **현재 구현은 단순화된 1차 버전**:
    /// - PCM 버퍼를 누적해서 30초마다 임시 파일로 flush 후 file-based transcribe 호출
    /// - hop/overlap 정교화는 후속 PR
    public func liveTranscriptionStream(from input: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                var collected: [AVAudioPCMBuffer] = []
                var totalFrames: AVAudioFrameCount = 0
                var sampleRate: Double = 16_000
                let chunkSeconds = 30.0
                var chunkIndex = 0

                for await buffer in input {
                    if Task.isCancelled { break }
                    collected.append(buffer)
                    totalFrames += buffer.frameLength
                    sampleRate = buffer.format.sampleRate

                    if Double(totalFrames) / sampleRate >= chunkSeconds {
                        if let url = Self.flushChunk(buffers: collected) {
                            do {
                                let pipe = try await self.ensurePipe()
                                let results = try await pipe.transcribe(audioPath: url.path)
                                let baseOffset = Double(chunkIndex) * chunkSeconds
                                for utt in Self.convertToUtterances(results, offset: baseOffset) {
                                    continuation.yield(utt)
                                }
                                try? FileManager.default.removeItem(at: url)
                            } catch {
                                #if DEBUG
                                print("[WhisperKitEngine] 청크 전사 실패: \(error)")
                                #endif
                            }
                        }
                        collected.removeAll(keepingCapacity: true)
                        totalFrames = 0
                        chunkIndex += 1
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pipe management

    private func ensurePipe() async throws -> WhisperKit {
        if let existing = await box.current() { return existing }
        let new = try await WhisperKit(WhisperKitConfig(model: modelName))
        return await box.setIfNil(new)
    }

    // MARK: - Conversion helpers

    /// `[TranscriptionResult]` → `[Utterance]`. WhisperKit 의 segments 가
    /// 비어있으면 전체 텍스트를 단일 utterance 로 반환한다.
    static func convertToUtterances(
        _ results: [TranscriptionResult],
        offset: Double = 0
    ) -> [Utterance] {
        var utts: [Utterance] = []
        for r in results {
            if r.segments.isEmpty {
                let text = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                utts.append(Utterance(
                    speaker: Speaker(id: "?", label: "?"),
                    text: text,
                    startSeconds: offset,
                    endSeconds: offset + 0,
                    confidence: 1.0
                ))
            } else {
                for seg in r.segments {
                    let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    utts.append(Utterance(
                        speaker: Speaker(id: "?", label: "?"),
                        text: text,
                        startSeconds: Double(seg.start) + offset,
                        endSeconds: Double(seg.end) + offset,
                        confidence: 1.0
                    ))
                }
            }
        }
        return utts
    }

    /// 누적된 PCM 버퍼들을 임시 .wav 파일로 flush.
    /// 16kHz mono PCM 변환은 호출자가 미리 해두어야 한다 (현재는 입력 그대로).
    private static func flushChunk(buffers: [AVAudioPCMBuffer]) -> URL? {
        guard let first = buffers.first else { return nil }
        let format = first.format
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisperkit-\(UUID().uuidString).caf")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            for buf in buffers {
                try file.write(from: buf)
            }
            return url
        } catch {
            #if DEBUG
            print("[WhisperKitEngine] flushChunk 실패: \(error)")
            #endif
            return nil
        }
    }
}
