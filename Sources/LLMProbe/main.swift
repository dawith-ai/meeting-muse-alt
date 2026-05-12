import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence FoundationModels 검증 프로브.
///
/// 사용법:
///   swift run LLMProbe "요약할 텍스트나 질문"
///
/// 실행 환경:
///   - macOS 26+
///   - Apple Intelligence 활성화 (설정 → Apple Intelligence)
///   - 시스템 모델 다운로드 완료
///
/// 미충족 시 가용성 사유를 출력하고 종료.

let args = CommandLine.arguments
let prompt = args.count >= 2 ? args[1] : "한국어로 자기소개를 두 문장으로 해주세요."

#if canImport(FoundationModels)
if #available(macOS 26.0, *) {
    let model = SystemLanguageModel.default
    print("→ 시스템 모델 가용성 검사...")
    switch model.availability {
    case .available:
        print("✓ available")
    case .unavailable(let reason):
        let reasonText: String
        switch reason {
        case .deviceNotEligible:
            reasonText = "기기 미지원 (Apple Silicon + Apple Intelligence 필요)"
        case .appleIntelligenceNotEnabled:
            reasonText = "Apple Intelligence 비활성 (설정 → Apple Intelligence)"
        case .modelNotReady:
            reasonText = "모델 다운로드 중 (잠시 후 재시도)"
        @unknown default:
            reasonText = "알 수 없는 사유"
        }
        FileHandle.standardError.write("✗ unavailable: \(reasonText)\n".data(using: .utf8)!)
        exit(2)
    @unknown default:
        FileHandle.standardError.write("✗ unknown availability\n".data(using: .utf8)!)
        exit(2)
    }

    print("→ 추론 시작 (prompt = \"\(prompt)\")")
    let started = Date()
    do {
        let session = LanguageModelSession(instructions: "당신은 도움이 되는 한국어 어시스턴트입니다.")
        let response = try await session.respond(to: prompt)
        let elapsed = Date().timeIntervalSince(started)
        print("✓ 응답 (\(String(format: "%.2f", elapsed))s):")
        print(response.content)
        exit(0)
    } catch {
        FileHandle.standardError.write("✗ 추론 실패: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(3)
    }
} else {
    FileHandle.standardError.write("✗ macOS 26 미만 — FoundationModels 미지원\n".data(using: .utf8)!)
    exit(2)
}
#else
FileHandle.standardError.write("✗ FoundationModels SDK 없음\n".data(using: .utf8)!)
exit(2)
#endif
