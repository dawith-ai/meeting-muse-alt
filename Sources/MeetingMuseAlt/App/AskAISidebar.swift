import SwiftUI

/// Ask AI 사이드바 — 회의 전사에 대한 자연어 Q&A.
///
/// `OpenAIAskAI` (현재 유일 구현체) 가 OpenAI API 키를 필요로 한다.
/// 키 미입력 시 일반 안내 메시지를 표시한다.
@MainActor
public struct AskAISidebar: View {
    public let utterances: [Utterance]
    public let apiKeyProvider: () -> String?
    public let languageHint: String

    @State private var history: [AskAIMessage] = []
    @State private var draft: String = ""
    @State private var isWorking = false
    @State private var lastError: String?

    public init(
        utterances: [Utterance],
        apiKeyProvider: @escaping () -> String?,
        languageHint: String = "ko"
    ) {
        self.utterances = utterances
        self.apiKeyProvider = apiKeyProvider
        self.languageHint = languageHint
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if history.isEmpty && !isWorking {
                emptyState
            } else {
                chatLog
            }
            Divider()
            inputBar
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.tint)
            Text("Ask AI").font(.headline)
            Spacer()
            if !history.isEmpty {
                Button("지우기") { history = []; lastError = nil }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("회의 내용에 대해 질문하세요")
                .font(.callout)
            Text("예: \"결정된 액션 아이템을 정리해줘\", \"발화자 A가 마케팅에 대해 뭐라고 했어?\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var chatLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(history) { msg in
                        chatBubble(msg).id(msg.id)
                    }
                    if isWorking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("생각 중...").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                    }
                    if let err = lastError {
                        Text("오류: \(err)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(12)
            }
            .onChange(of: history.count) { _, _ in
                if let last = history.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func chatBubble(_ msg: AskAIMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .assistant {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .frame(width: 20)
            } else {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(msg.role == .assistant ? "AI" : "나")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(msg.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(msg.role == .assistant
                      ? Color.accentColor.opacity(0.08)
                      : Color.secondary.opacity(0.08))
        )
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("질문 입력...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit { send() }
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isWorking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Action

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard let key = apiKeyProvider(), !key.isEmpty else {
            lastError = "설정에서 OpenAI API 키를 입력하세요."
            return
        }
        draft = ""
        let userMsg = AskAIMessage(role: .user, content: question)
        history.append(userMsg)
        isWorking = true
        lastError = nil

        let service = OpenAIAskAI(apiKey: key)
        let snapshotHistory = history
        let utterancesSnapshot = utterances
        Task { @MainActor in
            do {
                let answer = try await service.ask(
                    utterances: utterancesSnapshot,
                    history: snapshotHistory.dropLast().map { $0 }, // exclude the just-added user msg
                    question: question,
                    languageHint: languageHint
                )
                history.append(AskAIMessage(role: .assistant, content: answer))
            } catch {
                lastError = error.localizedDescription
            }
            isWorking = false
        }
    }
}
