import Foundation
import AVFoundation

/// 전사 엔진의 공통 인터페이스. `WhisperEngine`이 기본 구현체이지만,
/// 테스트나 대체 엔진 (CoreML 모델, AssemblyAI fallback 등) 으로 교체 가능.
public protocol TranscriptionService: Sendable {
    /// 파일 단위 전사 — 녹음이 끝난 후 호출.
    func transcribe(audioURL: URL) async throws -> [Utterance]

    /// 라이브 전사 — 마이크/시스템 오디오 PCM 버퍼 스트림을 받아
    /// 부분 결과를 발화 단위로 송출.
    func liveTranscriptionStream(from input: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<Utterance>
}
