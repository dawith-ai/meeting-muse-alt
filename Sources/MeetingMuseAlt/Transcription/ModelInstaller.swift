import Foundation

/// Whisper.cpp ggml 모델 + CoreML 인코더 설치 헬퍼.
///
/// 모델 파일은 사용자별 `Application Support` 디렉터리에 보관합니다:
///   `~/Library/Application Support/MeetingMuseAlt/Models/`
///
/// 구성:
///   - `ggml-{name}.bin`            — whisper.cpp ggml weights (필수)
///   - `ggml-{name}-encoder.mlmodelc` — CoreML 인코더 (선택, Apple Silicon 가속)
///
/// CoreML `.mlmodelc` 는 별도로 생성해야 합니다.
/// 자세한 절차는 whisper.cpp 공식 가이드를 참고하세요:
///   https://github.com/ggerganov/whisper.cpp#core-ml-support
/// 요약: `models/generate-coreml-model.sh base` 실행 후 결과 `.mlmodelc` 디렉터리를
/// 위 Models 경로에 복사합니다 (Python + `coremltools` 필요).
public enum ModelInstaller {

    /// 모델 디렉터리 (기본: `Application Support/MeetingMuseAlt/Models`).
    /// 디렉터리는 lazy 생성되며, 호출 시점에 존재가 보장됩니다.
    public static func defaultModelDirectory() -> URL {
        let fm = FileManager.default
        let base: URL
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            base = appSupport
        } else {
            // Fallback — should not normally happen on macOS.
            base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        let dir = base
            .appendingPathComponent("MeetingMuseAlt", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 지정된 모델의 ggml weights 경로.
    public static func modelURL(name: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? defaultModelDirectory()
        return dir.appendingPathComponent("ggml-\(name).bin", isDirectory: false)
    }

    /// 지정된 모델의 CoreML 인코더 디렉터리 경로 (`.mlmodelc`).
    public static func coreMLEncoderURL(name: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? defaultModelDirectory()
        return dir.appendingPathComponent("ggml-\(name)-encoder.mlmodelc", isDirectory: true)
    }

    /// 모델 weights 파일 존재 여부. CoreML 인코더는 선택사항이므로 검사하지 않습니다.
    public static func isModelInstalled(name: String, in directory: URL? = nil) -> Bool {
        let url = modelURL(name: name, in: directory)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// HuggingFace 공식 mirror 의 추천 다운로드 URL.
    /// 예: `ggml-base.bin` → `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin`
    public static func suggestedDownloadURL(name: String) -> URL {
        // swiftlint:disable:next force_unwrapping
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!
    }

    /// 모델이 설치돼 있지 않으면 HuggingFace 에서 내려받아 설치.
    ///
    /// **현재 상태**: 본 구현은 골격(skeleton)이며, 실제 progress 보고나 재시도,
    /// SHA 검증 등은 후속 PR에서 추가합니다. 네트워크가 불가하거나 다운로드가
    /// 실패하면 `WhisperEngineError.modelMissing` 을 던집니다.
    ///
    /// - Parameters:
    ///   - name: 모델 이름 (예: `base`, `small`, `medium`).
    ///   - directory: 설치 대상 디렉터리 (테스트 주입용, 기본은 Application Support).
    ///   - progress: 0.0~1.0 진행률 콜백 (현재는 시작/종료 두 지점만 호출됩니다).
    public static func downloadIfNeeded(
        name: String,
        in directory: URL? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        let targetDir = directory ?? defaultModelDirectory()
        if isModelInstalled(name: name, in: targetDir) {
            progress?(1.0)
            return
        }

        progress?(0.0)
        let remote = suggestedDownloadURL(name: name)
        let target = modelURL(name: name, in: targetDir)

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw WhisperEngineError.modelMissing
            }
            let fm = FileManager.default
            // Ensure parent exists (defensive — defaultModelDirectory already creates it).
            try fm.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.moveItem(at: tempURL, to: target)
            progress?(1.0)
        } catch {
            // Network unavailable, 404, sandbox denial, etc.
            throw WhisperEngineError.modelMissing
        }
    }
}
