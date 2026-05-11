import Testing
import Foundation
@testable import MeetingMuseAlt

/// `ModelInstaller` 및 `WhisperEngine` 의 모델 lookup/폴백 동작 검증.
///
/// 이 테스트들은 사용자 Application Support 디렉터리를 건드리지 않기 위해
/// 임시 디렉터리를 주입합니다 (`WhisperEngine(modelDirectory:)`).

@Test func modelInstallerReportsFalseInEmptyDirectory() throws {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory
        .appendingPathComponent("MeetingMuseAltTests-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }

    #expect(ModelInstaller.isModelInstalled(name: "base", in: tempDir) == false)
}

@Test func modelInstallerSuggestedURLPointsAtHuggingFace() {
    let url = ModelInstaller.suggestedDownloadURL(name: "base")
    #expect(url.absoluteString == "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
}

@Test func modelInstallerDetectsExistingFile() throws {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory
        .appendingPathComponent("MeetingMuseAltTests-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }

    let modelURL = ModelInstaller.modelURL(name: "base", in: tempDir)
    try Data([0x00, 0x01, 0x02]).write(to: modelURL)

    #expect(ModelInstaller.isModelInstalled(name: "base", in: tempDir) == true)
}

@Test func whisperEngineRealModeFallsBackToStubWhenModelMissing() async throws {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory
        .appendingPathComponent("MeetingMuseAltTests-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempDir) }

    // 모델이 없는 임시 디렉터리를 가리키면 .real 요청은 stub 으로 폴백되어야 한다.
    let engine = WhisperEngine(mode: .real, modelName: "base", modelDirectory: tempDir)
    let url = URL(fileURLWithPath: "/tmp/nonexistent-meeting-muse-test.caf")
    let result = try await engine.transcribe(audioURL: url)
    #expect(!result.isEmpty)
}
