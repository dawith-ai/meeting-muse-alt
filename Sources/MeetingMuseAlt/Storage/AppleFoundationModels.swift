import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence 시스템 모델 기반 로컬 요약기.
///
/// **요구사항**: macOS 26+ + Apple Intelligence 활성화. 외부 모델 다운로드 없이
/// 시스템 LLM을 사용하므로 가장 깔끔하지만, 사용자가 시스템 설정에서 Apple
/// Intelligence 를 활성화해야 한다. 한국어 지원 여부는 시스템 모델 가용성에
/// 따라 달라진다 (현재 macOS 26.4 기준 영어 + 일부 언어 정식 지원).
///
/// 미지원 시 `SummarizationError.notImplemented` 던짐 — 호출자는
/// `OpenAISummarizer` 로 폴백.
public struct AppleFoundationSummarizer: SummarizationService {
    public init() {}

    public func summarize(
        utterances: [Utterance],
        title: String?,
        languageHint: String
    ) async throws -> String {
        if utterances.isEmpty { throw SummarizationError.emptyUtterances }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await runFoundationModels(
                utterances: utterances,
                title: title,
                languageHint: languageHint
            )
        } else {
            throw SummarizationError.notImplemented
        }
        #else
        throw SummarizationError.notImplemented
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func runFoundationModels(
        utterances: [Utterance],
        title: String?,
        languageHint: String
    ) async throws -> String {
        // 시스템 모델 가용성 검사 — Apple Intelligence 비활성화 시 .unavailable.
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable:
            throw SummarizationError.notImplemented
        @unknown default:
            throw SummarizationError.notImplemented
        }

        let langName: String = {
            switch languageHint {
            case "ko": return "한국어"
            case "en": return "English"
            case "ja": return "日本語"
            case "zh": return "中文"
            default:   return languageHint
            }
        }()
        let titlePrefix = title.map { "회의 제목: \($0)\n\n" } ?? ""
        let transcript = OpenAISummarizer.formatTranscript(utterances)

        let instructions = """
            당신은 회의록 요약 전문가입니다. 입력된 전사를 \(langName) 마크다운으로 요약하세요.
            반드시 다음 섹션을 포함하세요:
            ## 핵심 요약
            ## 주요 논의 사항
            ## 결정 사항
            ## 액션 아이템 (담당자/기한)
            전사에 없는 내용은 추측하지 마세요.
            """
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: titlePrefix + "전사:\n" + transcript)
            return response.content
        } catch {
            throw SummarizationError.decoding(error.localizedDescription)
        }
    }
    #endif
}

/// Apple Intelligence 기반 로컬 Q&A (Ask AI).
public struct AppleFoundationAskAI: AskAIService {
    public init() {}

    public func ask(
        utterances: [Utterance],
        history: [AskAIMessage],
        question: String,
        languageHint: String
    ) async throws -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AskAIError.emptyQuestion }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw AskAIError.network("Apple Intelligence 시스템 모델 미사용 가능 (설정에서 활성화 필요)")
            }
            let langName: String = languageHint == "ko" ? "한국어" : languageHint
            let transcript = OpenAIAskAI.formatTranscript(utterances)
            let instructions = """
                당신은 회의 내용을 깊이 이해하고 정확하게 답변하는 어시스턴트입니다.
                제공된 전사 안에서만 답하세요. 전사에 없는 사실은 추측하지 말고 \
                "전사에서 확인할 수 없음" 이라고 답하세요. 답변은 \(langName) 로 작성하세요.
                전사:
                \(transcript)
                """

            // 이전 대화는 사용자 프롬프트에 동봉 (LanguageModelSession 의 단일-shot 사용 패턴).
            var historyText = ""
            for msg in history.suffix(10) {
                let prefix = msg.role == .user ? "사용자" : "어시스턴트"
                historyText += "\(prefix): \(msg.content)\n"
            }

            let session = LanguageModelSession(instructions: instructions)
            do {
                let prompt = (historyText.isEmpty ? "" : "이전 대화:\n\(historyText)\n") + "현재 질문: \(trimmed)"
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                throw AskAIError.decoding(error.localizedDescription)
            }
        }
        #endif
        throw AskAIError.network("Apple Intelligence (macOS 26+) 미지원 환경")
    }
}

/// Apple Intelligence 기반 로컬 번역.
public struct AppleFoundationTranslator: TranslationService {
    public init() {}

    public func translate(texts: [String], targetLang: String) async throws -> [String] {
        if texts.isEmpty { throw TranslationError.emptyInput }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw TranslationError.notImplemented
            }
            guard let langName = OpenAITranslator.supportedLanguages[targetLang] else {
                throw TranslationError.unsupportedLanguage(targetLang)
            }
            let clean = texts.map { String($0.prefix(OpenAITranslator.maxTextLength)) }
            let numbered = clean.enumerated()
                .map { "\($0.offset + 1). \($0.element.replacingOccurrences(of: "\n", with: " "))" }
                .joined(separator: "\n")

            let instructions = """
                You are a professional meeting transcript translator. Translate each numbered \
                line to \(langName). Preserve the numbering exactly. Output ONLY the numbered \
                translations, one per line, no commentary. Keep the same number of output lines \
                as input lines.
                """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: numbered)
                return OpenAITranslator.parseNumberedLines(raw: response.content, expectedCount: clean.count)
            } catch {
                throw TranslationError.decoding(error.localizedDescription)
            }
        }
        #endif
        throw TranslationError.notImplemented
    }
}

// MARK: - 가용성 검사 헬퍼

public enum AppleFoundationModels {
    /// Apple Intelligence 가 현재 시스템에서 사용 가능한지 검사.
    /// macOS 26 미만 또는 Apple Intelligence 미활성 시 `false`.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
            return false
        }
        return false
        #else
        return false
        #endif
    }

    /// 미사용 가능 시 사유 (있다면) — UI 에 표시.
    public static var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let reason):
                return Self.describe(reason)
            @unknown default:
                return "알 수 없는 가용성 상태"
            }
        }
        return "macOS 26 이상이 필요합니다."
        #else
        return "FoundationModels SDK 가 빌드 환경에 없습니다."
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "이 기기는 Apple Intelligence 를 지원하지 않습니다."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence 가 활성화되지 않았습니다 (설정 → Apple Intelligence)."
        case .modelNotReady:
            return "시스템 모델이 아직 준비되지 않았습니다 (다운로드 중일 수 있음)."
        @unknown default:
            return "Apple Intelligence 사용 불가"
        }
    }
    #endif
}
