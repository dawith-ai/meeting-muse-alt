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

        // 1) CoreML 모델 로드 (.mlpackage → compiled .mlmodelc)
        let compiledURL: URL
        do {
            compiledURL = try await MLModel.compileModel(at: expectedModelURL)
        } catch {
            throw PyannoteEngineError.inferenceFailed("CoreML 모델 컴파일 실패: \(error.localizedDescription)")
        }
        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .all
        let model: MLModel
        do {
            model = try MLModel(contentsOf: compiledURL, configuration: mlConfig)
        } catch {
            throw PyannoteEngineError.inferenceFailed("CoreML 모델 로드 실패: \(error.localizedDescription)")
        }

        // 2) 16kHz mono float32 로 리샘플 + 전체 샘플 추출
        let samples: [Float]
        do {
            samples = try Self.loadMono16kFloat(from: audioURL)
        } catch {
            throw PyannoteEngineError.inferenceFailed("오디오 리샘플 실패: \(error.localizedDescription)")
        }
        guard !samples.isEmpty else { return [] }

        // 3) 10초(160_000) 윈도우 슬라이딩으로 추론 → 발화 구간 추출.
        //    pyannote/segmentation-3.0 의 출력 shape는 (1, frames, 7) 이지만,
        //    coremltools 변환 결과의 출력 이름/shape 는 변환 시점에 따라 다를 수 있어
        //    여기서는 첫 번째 multi-array 출력을 자동으로 사용한다.
        let windowSize = 160_000
        let hopSize = 80_000 // 50% overlap
        var rawSegments: [DiarizationSegment] = []
        var windowStart = 0
        while windowStart < samples.count {
            let windowEnd = min(windowStart + windowSize, samples.count)
            let chunk = Array(samples[windowStart..<windowEnd])
            // 부족한 길이는 0-padding
            var padded = chunk
            if padded.count < windowSize {
                padded.append(contentsOf: [Float](repeating: 0, count: windowSize - padded.count))
            }
            do {
                let starts = Double(windowStart) / 16_000.0
                let detected = try Self.runWindow(model: model, samples: padded, windowOffsetSeconds: starts)
                rawSegments.append(contentsOf: detected)
            } catch {
                #if DEBUG
                print("[PyannoteEngine] window @ \(windowStart) failed: \(error)")
                #endif
            }
            windowStart += hopSize
        }

        // 4) 시간 정렬 + 인접 동일화자 머지
        return Self.mergeAdjacent(rawSegments)
    }

    /// 한 10초 윈도우에 대해 모델을 호출하고, 발화 구간을 0.5 임계로 추출.
    private static func runWindow(
        model: MLModel,
        samples: [Float],
        windowOffsetSeconds: Double
    ) throws -> [DiarizationSegment] {
        // 모델 입력 이름을 description에서 찾는다 (보통 "audio" 또는 "input").
        let inputDesc = model.modelDescription.inputDescriptionsByName
        guard let firstInputName = inputDesc.keys.first else {
            throw PyannoteEngineError.inferenceFailed("모델 입력 이름을 찾을 수 없습니다.")
        }
        // shape (1, 1, 160000) MultiArray 생성
        let array = try MLMultiArray(shape: [1, 1, NSNumber(value: samples.count)], dataType: .float32)
        for i in 0..<samples.count {
            array[i] = NSNumber(value: samples[i])
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            firstInputName: MLFeatureValue(multiArray: array)
        ])
        let prediction = try model.prediction(from: provider)

        // 첫 multiArray 출력을 사용. shape 는 보통 (1, frames, 7) — 활성/비활성 ×
        // 화자 조합. 여기서는 단순화하여 "어느 슬롯이라도 0.5 이상이면 발화" 로 처리.
        guard let outputName = prediction.featureNames.first(where: {
                prediction.featureValue(for: $0)?.multiArrayValue != nil
              }),
              let out = prediction.featureValue(for: outputName)?.multiArrayValue
        else {
            return []
        }
        // (1, frames, K) — frames 축 1, classes 축 2 가정
        let shape = out.shape.map(\.intValue)
        guard shape.count == 3 else { return [] }
        let frames = shape[1]
        let classes = shape[2]
        guard frames > 0, classes > 0 else { return [] }
        let frameSeconds = 10.0 / Double(frames) // 10초 윈도우

        var raws: [DiarizationSegment] = []
        var lastSpeaker: Int?
        var segmentStart: Double = 0
        for f in 0..<frames {
            // 각 frame 에서 activation 가장 큰 class 의 index
            var bestClass = -1
            var bestVal: Double = 0.5
            for k in 0..<classes {
                let idx = (0 * shape[1] * shape[2]) + (f * shape[2]) + k
                let v = out[idx].doubleValue
                if v > bestVal {
                    bestVal = v
                    bestClass = k
                }
            }
            if bestClass != lastSpeaker {
                if let prev = lastSpeaker, prev >= 0 {
                    let endTime = windowOffsetSeconds + Double(f) * frameSeconds
                    raws.append(DiarizationSegment(
                        speakerId: String(prev),
                        startSeconds: segmentStart,
                        endSeconds: endTime
                    ))
                }
                lastSpeaker = bestClass
                segmentStart = windowOffsetSeconds + Double(f) * frameSeconds
            }
        }
        if let prev = lastSpeaker, prev >= 0 {
            raws.append(DiarizationSegment(
                speakerId: String(prev),
                startSeconds: segmentStart,
                endSeconds: windowOffsetSeconds + 10
            ))
        }
        return raws
    }

    /// 시간 순 정렬 후 인접한 동일 화자 segment 머지.
    private static func mergeAdjacent(_ segments: [DiarizationSegment]) -> [DiarizationSegment] {
        let sorted = segments.sorted { $0.startSeconds < $1.startSeconds }
        var out: [DiarizationSegment] = []
        for seg in sorted {
            if let last = out.last,
               last.speakerId == seg.speakerId,
               seg.startSeconds <= last.endSeconds + 0.1 {
                out.removeLast()
                out.append(DiarizationSegment(
                    speakerId: last.speakerId,
                    startSeconds: last.startSeconds,
                    endSeconds: max(last.endSeconds, seg.endSeconds)
                ))
            } else {
                out.append(seg)
            }
        }
        return out
    }

    /// 오디오 파일을 16kHz mono float32 로 로드.
    private static func loadMono16kFloat(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let srcFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw PyannoteEngineError.inferenceFailed("타겟 포맷 생성 실패")
        }
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw PyannoteEngineError.inferenceFailed("입력 버퍼 할당 실패")
        }
        try file.read(into: inBuffer)

        // 변환
        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw PyannoteEngineError.inferenceFailed("출력 버퍼 할당 실패")
        }
        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            throw PyannoteEngineError.inferenceFailed("AVAudioConverter 생성 실패")
        }
        var consumed = false
        var convErr: NSError?
        converter.convert(to: outBuffer, error: &convErr) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .endOfStream
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return inBuffer
        }
        if let convErr {
            throw PyannoteEngineError.inferenceFailed("리샘플 실패: \(convErr.localizedDescription)")
        }
        guard let ch = outBuffer.floatChannelData?[0] else {
            throw PyannoteEngineError.inferenceFailed("float channel data 없음")
        }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuffer.frameLength)))
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
