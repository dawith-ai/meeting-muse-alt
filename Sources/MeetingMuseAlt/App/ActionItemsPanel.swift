import SwiftUI

/// 회의 요약(마크다운)에서 추출한 액션 아이템 패널.
public struct ActionItemsPanel: View {
    public let summaryMarkdown: String?
    public init(summaryMarkdown: String?) { self.summaryMarkdown = summaryMarkdown }

    public var body: some View {
        let items = (summaryMarkdown.map(ActionItemExtractor.extract(from:))) ?? []
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checklist").foregroundStyle(.tint)
                        Text("액션 아이템 \(items.count)건").font(.headline)
                    }
                    .padding(.bottom, 4)
                    ForEach(items) { item in
                        row(item)
                        Divider()
                    }
                }
                .padding(16)
            }
        }
    }

    private func row(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.task).font(.body)
                if item.assignee != nil || item.dueText != nil || item.priority != nil {
                    HStack(spacing: 6) {
                        if let a = item.assignee {
                            Label(a, systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let due = item.dueText {
                            Label(due, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let p = item.priority {
                            Text(p.label)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(priorityColor(p).opacity(0.2))
                                .foregroundStyle(priorityColor(p))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func priorityColor(_ p: ActionItem.Priority) -> Color {
        switch p {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .secondary
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("액션 아이템 없음")
                .font(.callout)
            Text("회의 요약을 생성하면 액션 아이템이 자동으로 추출됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
