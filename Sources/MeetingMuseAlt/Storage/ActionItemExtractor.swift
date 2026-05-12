import Foundation

/// 회의 요약에서 추출된 액션 아이템 한 건.
public struct ActionItem: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var task: String
    /// 담당자 (감지된 경우)
    public var assignee: String?
    /// 기한 (감지된 경우, 자유 텍스트 — "2026-05-20" 또는 "다음 주 금요일" 등)
    public var dueText: String?
    /// 우선순위 (감지된 경우)
    public var priority: Priority?

    public enum Priority: String, Hashable, Sendable, Codable {
        case high, medium, low

        public var label: String {
            switch self {
            case .high:   return "높음"
            case .medium: return "보통"
            case .low:    return "낮음"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        task: String,
        assignee: String? = nil,
        dueText: String? = nil,
        priority: Priority? = nil
    ) {
        self.id = id
        self.task = task
        self.assignee = assignee
        self.dueText = dueText
        self.priority = priority
    }
}

/// 마크다운 회의록에서 액션 아이템 섹션을 추출/파싱.
///
/// `OpenAISummarizer` 가 만든 마크다운 요약의 `## 액션 아이템` 섹션을 처리하지만,
/// 일반적인 bullet 패턴도 인식한다. 외부 의존성 0, 순수 함수.
public enum ActionItemExtractor {
    /// 마크다운에서 액션 아이템을 추출.
    public static func extract(from markdown: String) -> [ActionItem] {
        let sectionLines = actionSectionLines(markdown: markdown)
        if !sectionLines.isEmpty {
            return parseBullets(lines: sectionLines)
        }
        // 섹션이 명시되지 않으면 — 전체에서 bullet 들을 시도
        let allLines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return parseBullets(lines: allLines)
    }

    /// `## 액션 아이템` / `## Action Items` / `## TODO` 등 헤더 아래의 라인을 모음.
    static func actionSectionLines(markdown: String) -> [String] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let headerKeywords = ["액션 아이템", "Action Items", "Action items", "TODO", "할 일", "할일", "후속 조치"]
        var capturing = false
        var collected: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let isHeader = line.hasPrefix("#")
            if isHeader {
                let lower = line.lowercased()
                if headerKeywords.contains(where: { lower.contains($0.lowercased()) }) {
                    capturing = true
                    continue
                }
                if capturing {
                    // 새로운 헤더 — 캡처 종료
                    break
                }
            }
            if capturing { collected.append(raw) }
        }
        return collected
    }

    /// `- 작업 (담당: 홍길동, 기한: 2026-05-20, 우선순위: 높음)` 패턴 파싱.
    static func parseBullets(lines: [String]) -> [ActionItem] {
        var out: [ActionItem] = []
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard let body = stripBulletMarker(trimmed) else { continue }
            if body.isEmpty { continue }
            // 메타 분리
            let (task, meta) = splitMeta(body)
            if task.isEmpty { continue }
            var assignee: String? = nil
            var dueText: String? = nil
            var priority: ActionItem.Priority? = nil
            for (keyRaw, valueRaw) in meta {
                let key = keyRaw.lowercased()
                let value = valueRaw.trimmingCharacters(in: .whitespaces)
                if key.contains("담당") || key.contains("assignee") || key.contains("owner") {
                    assignee = value
                } else if key.contains("기한") || key.contains("due") || key.contains("deadline") {
                    dueText = value
                } else if key.contains("우선") || key.contains("priority") {
                    if value.contains("높") || value.lowercased().contains("high") {
                        priority = .high
                    } else if value.contains("낮") || value.lowercased().contains("low") {
                        priority = .low
                    } else {
                        priority = .medium
                    }
                }
            }
            out.append(ActionItem(
                task: task,
                assignee: assignee,
                dueText: dueText,
                priority: priority
            ))
        }
        return out
    }

    private static func stripBulletMarker(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // 지원: `-`, `*`, `•`, 숫자.
        if let r = trimmed.range(of: #"^[-*•]\s+"#, options: .regularExpression) {
            return String(trimmed[r.upperBound...])
        }
        if let r = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            return String(trimmed[r.upperBound...])
        }
        return nil
    }

    /// `작업 (담당: A, 기한: B)` 형식 분리.
    static func splitMeta(_ body: String) -> (task: String, meta: [(key: String, value: String)]) {
        // 마지막 괄호 쌍을 메타로 처리
        guard let openIdx = body.lastIndex(of: "("),
              let closeIdx = body.lastIndex(of: ")"),
              openIdx < closeIdx
        else {
            return (body.trimmingCharacters(in: .whitespaces), [])
        }
        let task = String(body[..<openIdx]).trimmingCharacters(in: .whitespaces)
        let metaRaw = String(body[body.index(after: openIdx)..<closeIdx])
        var meta: [(String, String)] = []
        for chunk in metaRaw.split(separator: ",") {
            let parts = chunk.split(separator: ":", maxSplits: 1).map { String($0) }
            if parts.count == 2 {
                meta.append((parts[0].trimmingCharacters(in: .whitespaces),
                             parts[1].trimmingCharacters(in: .whitespaces)))
            }
        }
        return (task, meta)
    }
}
