import Foundation
import WhisperKit

/// WhisperKit 통합 검증용 CLI 프로브 — `MeetingMuseAlt` 와는 별도 executable.
///
/// 사용법:
///   swift run WhisperKitProbe <audio file path>
///
/// 첫 실행 시 `tiny` 모델 (~75MB) 이 HuggingFace 에서 자동 다운로드된다.
/// 두 번째 실행부터는 캐시 사용.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: WhisperKitProbe <audio file path>\n".data(using: .utf8)!)
    exit(2)
}

let audioPath = args[1]
guard FileManager.default.fileExists(atPath: audioPath) else {
    FileHandle.standardError.write("File not found: \(audioPath)\n".data(using: .utf8)!)
    exit(3)
}

print("→ WhisperKit 모델 초기화 (tiny) — 첫 실행 시 모델 다운로드...")
let started = Date()

do {
    let pipe = try await WhisperKit(WhisperKitConfig(model: "tiny"))
    let initElapsed = Date().timeIntervalSince(started)
    print("→ 모델 준비 완료 (\(String(format: "%.1f", initElapsed))s). 전사 시작...")

    let txStarted = Date()
    let results = try await pipe.transcribe(audioPath: audioPath)
    let txElapsed = Date().timeIntervalSince(txStarted)
    print("→ 전사 완료 (\(String(format: "%.2f", txElapsed))s)")

    for r in results {
        if r.segments.isEmpty {
            let trimmed = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print("  · \(trimmed)")
            }
        } else {
            for seg in r.segments {
                let t = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                print(String(format: "  [%6.2f → %6.2f] %@", seg.start, seg.end, t))
            }
        }
    }
    exit(0)
} catch {
    FileHandle.standardError.write("Error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
