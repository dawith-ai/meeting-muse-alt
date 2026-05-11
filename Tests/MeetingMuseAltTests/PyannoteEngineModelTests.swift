import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func pyannoteEngineReportsModelNotInstalledInEmptyTempDir() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pyannote-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let engine = PyannoteEngine(modelDirectory: tmp)
    #expect(engine.isModelInstalled == false)
    #expect(engine.expectedModelURL.lastPathComponent == "pyannote-segmentation-3.0.mlpackage")
}

@Test func pyannoteEngineDetectsModelDirectoryPresence() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pyannote-detect-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // .mlpackage 은 디렉토리이므로 디렉토리 생성으로 시뮬레이션
    let modelDir = tmp.appendingPathComponent("pyannote-segmentation-3.0.mlpackage", isDirectory: true)
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

    let engine = PyannoteEngine(modelDirectory: tmp)
    #expect(engine.isModelInstalled == true)
}

@Test func pyannoteSegmentThrowsWhenModelMissing() async {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pyannote-missing-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let engine = PyannoteEngine(modelDirectory: tmp)
    do {
        _ = try await engine.segment(audioURL: URL(fileURLWithPath: "/dev/null"))
        Issue.record("Expected modelMissing")
    } catch let e as PyannoteEngineError {
        if case .modelMissing = e { /* pass */ }
        else { Issue.record("Unexpected: \(e)") }
    } catch {
        Issue.record("Unexpected: \(error)")
    }
}
