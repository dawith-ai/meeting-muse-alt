import Foundation

/// 회의록 익스포트용 페이로드.
public struct MeetingExportData: Sendable {
    public var title: String
    public var createdAt: Date
    public var durationSeconds: Double
    public var language: String
    public var summary: String?
    public var utterances: [Utterance]

    public init(
        title: String,
        createdAt: Date = Date(),
        durationSeconds: Double,
        language: String = "ko",
        summary: String? = nil,
        utterances: [Utterance]
    ) {
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.language = language
        self.summary = summary
        self.utterances = utterances
    }
}

public enum MeetingExportFormat: Sendable {
    case html
    case markdown
    case plainText

    public var fileExtension: String {
        switch self {
        case .html:      return "html"
        case .markdown:  return "md"
        case .plainText: return "txt"
        }
    }
}

/// 회의록 익스포트.
///
/// HTML 출력은 외부 자산이 없는 self-contained 단일 파일로, 인라인 스타일을
/// 포함합니다. 모든 동적 텍스트는 escape 처리하여 XSS 위험을 차단합니다.
public final class MeetingExporter: Sendable {
    public init() {}

    public func render(_ data: MeetingExportData, as format: MeetingExportFormat) -> String {
        switch format {
        case .html:      return renderHTML(data)
        case .markdown:  return renderMarkdown(data)
        case .plainText: return renderPlainText(data)
        }
    }

    public func write(_ data: MeetingExportData, to url: URL, as format: MeetingExportFormat) throws {
        let content = render(data, as: format)
        try content.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    // MARK: - HTML

    private func renderHTML(_ data: MeetingExportData) -> String {
        let escapedTitle = Self.htmlEscape(data.title)
        let isoDate = Self.iso8601Formatter.string(from: data.createdAt)
        let humanDate = Self.localeFormatter(language: data.language).string(from: data.createdAt)
        let duration = Self.formatDuration(data.durationSeconds)
        let summarySection: String
        if let s = data.summary, !s.isEmpty {
            summarySection = """
                <section class="summary">
                  <h2>요약</h2>
                  <p>\(Self.htmlEscape(s))</p>
                </section>
                """
        } else {
            summarySection = ""
        }

        var rows = ""
        if data.utterances.isEmpty {
            rows = #"<li class="empty">발화 없음</li>"#
        } else {
            for utt in data.utterances {
                let color = Self.speakerColorHSL(speakerID: utt.speaker.id)
                let chip = Self.htmlEscape(utt.speaker.label)
                let ts = Self.htmlEscape(utt.timestampLabel)
                let text = Self.htmlEscape(utt.text)
                rows += """
                    <li class="utt">
                      <span class="ts">\(ts)</span>
                      <span class="chip" style="background:\(color)">\(chip)</span>
                      <p class="text">\(text)</p>
                    </li>
                    """
            }
        }

        return """
            <!DOCTYPE html>
            <html lang="\(Self.htmlEscape(data.language))">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>\(escapedTitle)</title>
              <style>
                :root { color-scheme: light dark; }
                body { font-family: -apple-system, system-ui, BlinkMacSystemFont, sans-serif; max-width: 760px; margin: 32px auto; padding: 0 16px; color: #1a1a1a; }
                header { border-bottom: 1px solid #e0e0e0; padding-bottom: 16px; margin-bottom: 24px; }
                h1 { margin: 0 0 8px; font-size: 22px; }
                .meta { color: #666; font-size: 12px; display: flex; gap: 12px; flex-wrap: wrap; }
                .badge { background: #2b6cb0; color: #fff; padding: 1px 8px; border-radius: 999px; font-size: 11px; }
                .summary { background: #f6f8fb; border-left: 3px solid #2b6cb0; padding: 12px 16px; margin: 24px 0; border-radius: 6px; }
                .summary h2 { margin: 0 0 6px; font-size: 14px; color: #2b6cb0; }
                .summary p { margin: 0; font-size: 14px; line-height: 1.6; }
                ul.utterances { list-style: none; padding: 0; margin: 0; }
                li.utt { display: grid; grid-template-columns: 56px auto 1fr; gap: 8px 12px; align-items: start; padding: 10px 0; border-bottom: 1px solid #f0f0f0; }
                li.empty { text-align: center; color: #999; padding: 24px 0; }
                .ts { font-family: ui-monospace, "SF Mono", monospace; font-size: 11px; color: #888; padding-top: 4px; }
                .chip { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 600; color: #fff; }
                .text { margin: 0; line-height: 1.6; font-size: 14px; }
                @media (prefers-color-scheme: dark) {
                  body { color: #eee; background: #1a1a1a; }
                  header { border-color: #333; }
                  .meta { color: #999; }
                  .summary { background: #20283a; }
                  li.utt { border-color: #2a2a2a; }
                  .ts { color: #aaa; }
                }
              </style>
            </head>
            <body>
              <header>
                <h1>\(escapedTitle)</h1>
                <div class="meta">
                  <time datetime="\(Self.htmlEscape(isoDate))">\(Self.htmlEscape(humanDate))</time>
                  <span>⏱ \(Self.htmlEscape(duration))</span>
                  <span class="badge">\(Self.htmlEscape(data.language.uppercased()))</span>
                </div>
              </header>
              \(summarySection)
              <ul class="utterances">
                \(rows)
              </ul>
            </body>
            </html>
            """
    }

    // MARK: - Markdown

    private func renderMarkdown(_ data: MeetingExportData) -> String {
        let humanDate = Self.localeFormatter(language: data.language).string(from: data.createdAt)
        let duration = Self.formatDuration(data.durationSeconds)
        var out = "# \(data.title)\n\n"
        out += "_\(humanDate) — ⏱ \(duration) — \(data.language.uppercased())_\n\n"

        if let s = data.summary, !s.isEmpty {
            out += "## 요약\n\n\(s)\n\n"
        }

        out += "## 전사본\n\n"
        if data.utterances.isEmpty {
            out += "_발화 없음_\n"
        } else {
            for utt in data.utterances {
                let ts = utt.timestampLabel
                let speaker = utt.speaker.label
                let safeText = utt.text.replacingOccurrences(of: "\n", with: " ")
                out += "- **\(ts)** [\(speaker)]: \(safeText)\n"
            }
        }
        return out
    }

    // MARK: - Plain text

    private func renderPlainText(_ data: MeetingExportData) -> String {
        let humanDate = Self.localeFormatter(language: data.language).string(from: data.createdAt)
        let duration = Self.formatDuration(data.durationSeconds)
        var out = "\(data.title)\n"
        out += "\(humanDate) — \(duration) — \(data.language.uppercased())\n\n"
        if let s = data.summary, !s.isEmpty {
            out += "[요약]\n\(s)\n\n"
        }
        for utt in data.utterances {
            let safeText = utt.text.replacingOccurrences(of: "\n", with: " ")
            out += "[\(utt.timestampLabel)] \(utt.speaker.label): \(safeText)\n"
        }
        return out
    }

    // MARK: - Helpers

    /// HTML 5 attribute-safe escape: `& < > " '`
    static func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// 화자 ID로부터 결정론적 HSL 컬러를 생성 (CSS hsl(...) 문자열).
    static func speakerColorHSL(speakerID: String) -> String {
        var hasher = HashingIterator()
        for byte in speakerID.utf8 {
            hasher.update(byte)
        }
        let hash = hasher.finalize()
        let hue = Int(hash % 360)
        return "hsl(\(hue), 55%, 48%)"
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func localeFormatter(language: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: language)
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }
}

/// FNV-1a 변형의 결정론적 해시 — Swift `hashValue` 가 프로세스마다 달라지는
/// 문제를 피하기 위해 직접 구현. 익스포트된 HTML 색상이 회의 라이프타임
/// 전체에서 동일하게 유지되도록 보장합니다.
private struct HashingIterator {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a 64-bit offset basis

    mutating func update(_ byte: UInt8) {
        value ^= UInt64(byte)
        value = value &* 0x100_0000_01b3 // FNV prime
    }

    func finalize() -> UInt64 { value }
}
