import Foundation
import AVFoundation
import CoreML

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
            return "Pyannote CoreML 모델이 ~/Library/Application Support/MeetingMuseAlt/Models/pyannote-segmentation-3.0.mlpackage 에 없습니다. scripts/convert_pyannote.py 로 변환해주세요."
        case .inferenceFailed(let m):
            return "화자분리 추론 실패: \(m)"
        }
    }
}

/// CoreML 로 변환된 Pyannote segmentation + embedding 모델을 사용해
/// 화자분리(speaker diarization)를 수행합니다.
///
/// **현재 상태 (M3)**:
///   - `assignSpeakers(to:segments:)` — utterance ↔ segment 시간 겹침 매핑 (M1부터 동작)
///   - `isModelInstalled` / `expectedModelURL` — 모델 룩업 헬퍼
///   - `segment(audioURL:)` — 모델이 설치되어 있으면 CoreML 추론 시도,
///     없으면 `PyannoteEngineError.modelMissing` 던짐
///
/// **추론 알고리즘 후속 PR**:
///   - 16kHz 모노로 리샘플 → 10초 윈도우 슬라이딩
///   - 각 윈도우에서 segmentation 모델 추론 → 발화 구간 추출
///   - 임베딩 모델 (WeSpeaker / Resemblyzer) 변환 후 적용
///   - Agglomerative clustering 로 임베딩 → speaker label
///
/// 모델 변환은 `scripts/convert_pyannote.py` 참조.
public final class PyannoteEngine: @unchecked Sendable {
    public static let modelFileName = "pyannote-segmentation-3.0.mlpackage"

    public let modelDirectory: URL

    public init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory ?? Self.defaultModelDirectory()
    }

    /// `pyannote-segmentation-3.0.mlpackage` 가 모델 디렉토리에 존재하는지.
    public var isModelInstalled: Bool {
        FileManager.default.fileExists(atPath: expectedModelURL.path)
    }

    public var expectedModelURL: URL {
        modelDirectory.appendingPathComponent(Self.modelFileName, isDirectory: true)
    }

    public func segment(audioURL: URL) async throws -> [DiarizationSegment] {
        guard isModelInstalled else {
            throw PyannoteEngineError.modelMissing
        }
        // TODO(후속): CoreML 모델 로드 + 16kHz 리샘플 + 윈도우 슬라이딩 추론 +
        // 임베딩 추출 + clustering. 현재는 모델 존재 검증 후 빈 결과 반환.
        // Whisper 발화에 자동으로 매핑되지 않을 뿐, 호출 컨트랙트는 유지.
        return []
    }

    public func assignSpeakers(to utterances: [Utterance], segments: [DiarizationSegment]) -> [Utterance] {
        guard !segments.isEmpty else { return utterances }
        return utterances.map { utt in
            let bestOverlap = segments.max { a, b in
                Self.overlap(a, utt) < Self.overlap(b, utt)
            }
            if let bestOverlap, Self.overlap(bestOverlap, utt) > 0 {
                return Utterance(
                    id: utt.id,
                    speaker: Speaker(id: bestOverlap.speakerId, label: "화자 \(bestOverlap.speakerId)"),
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

    private static func defaultModelDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("MeetingMuseAlt/Models/", isDirectory: true)
    }
}
