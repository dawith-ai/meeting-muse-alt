import SwiftUI

/// 회의 메모 패널 — 자유 텍스트 노트 작성/편집/삭제.
@MainActor
public struct MemoPanel: View {
    @ObservedObject var store: MeetingNotesStore
    public let meetingID: UUID?

    @State private var draft = ""
    @State private var editingID: UUID?
    @State private var editingText = ""

    public init(store: MeetingNotesStore, meetingID: UUID? = nil) {
        self.store = store
        self.meetingID = meetingID
    }

    public var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()
            list
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("새 메모...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit { addNote() }
            Button {
                addNote()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        let visible = store.notes(forMeeting: meetingID)
        if visible.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("메모가 없습니다")
                    .font(.callout)
                Text("위에서 메모를 작성하거나, Cmd+Enter 로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { note in
                        row(note)
                        Divider()
                    }
                }
            }
        }
    }

    private func row(_ note: MeetingNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.dateFormatter.string(from: note.updatedAt))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if editingID == note.id {
                    Button("저장") {
                        store.update(id: note.id, text: editingText)
                        editingID = nil
                    }
                    .controlSize(.small)
                    Button("취소") { editingID = nil }
                        .controlSize(.small)
                } else {
                    Button {
                        editingID = note.id
                        editingText = note.text
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        store.remove(id: note.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if editingID == note.id {
                TextEditor(text: $editingText)
                    .frame(minHeight: 60)
                    .font(.body)
            } else {
                Text(note.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func addNote() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.add(text, meetingID: meetingID)
        draft = ""
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
