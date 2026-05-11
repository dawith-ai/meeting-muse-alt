import Foundation
import AVFoundation

public struct DiarizationSegment: Sendable {
    public let speakerId: String
    public let startSeconds: Double
    public let endSeconds: Double
}

public enum PyannoteEngineError: LocalizedError {
    case modelMissing
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Pyannote CoreML 모델이 번들에 포함되지 않았습니다."
        case .inferenceFailed(let m):
            return "화자분리 추론 실패: \(m)"
        }
    }
}

/// CoreML로 변환된 Pyannote segmentation + embedding 모델을 사용해
/// 화자분리(speaker diarization)를 수행합니다.
///
/// **상태 (M1)**: 인터페이스만 제공. 실제 추론은 M2 단계에서 다음으로 연결합니다:
///   1. `pyannote/segmentation-3.0` 모델을 coremltools로 .mlpackage 변환
///   2. embedding 모델 (e.g. WeSpeaker)을 동일하게 변환
///   3. agglomerative clustering로 임베딩 → speaker label
///   4. Whisper 발화 구간과 매핑
public final class PyannoteEngine: @unchecked Sendable {
    public init() {}

    public func segment(audioURL: URL) async throws -> [DiarizationSegment] {
        // TODO(M2): CoreML 추론
        return []
    }

    public func assignSpeakers(to utterances: [Utterance], segments: [DiarizationSegment]) -> [Utterance] {
        guard !segments.isEmpty else { return utterances }
        return utterances.map { utt in
            let overlap = segments.max { a, b in
                Self.overlap(a, utt) < Self.overlap(b, utt)
            }
            if let overlap, Self.overlap(overlap, utt) > 0 {
                return Utterance(
                    id: utt.id,
                    speaker: Speaker(id: overlap.speakerId, label: "화자 \(overlap.speakerId)"),
                    text: utt.text,
                    startSeconds: utt.startSeconds,
                    endSeconds: utt.endSeconds,
                    confidence: utt.confidence
                )
            }
            return utt
        }
    }

    private static func overlap(_ s: DiarizationSegment, _ u: Utterance) -> Double {
        let start = max(s.startSeconds, u.startSeconds)
        let end = min(s.endSeconds, u.endSeconds)
        return max(0, end - start)
    }
}
