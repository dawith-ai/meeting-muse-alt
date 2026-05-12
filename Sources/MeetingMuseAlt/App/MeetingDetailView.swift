import SwiftUI

/// 저장된 회의를 다시 열어 재생 + 발화 인터랙티브 표시 + 메타 편집.
@MainActor
public struct MeetingDetailView: View {
    public let record: MeetingRecord
    /// 회의 변경(제목, 요약 등) 시 호출되는 콜백 — 호출자(라이브러리)가 repository.update + 재로드.
    public let onUpdate: (MeetingRecord) -> Void

    @State private var editingTitle: String
    @State private var titleEditing = false
    @StateObject private var playback = AudioPlaybackController()

    public init(record: MeetingRecord, onUpdate: @escaping (MeetingRecord) -> Void) {
        self.record = record
        self.onUpdate = onUpdate
        self._editingTitle = State(initialValue: record.title)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AudioPlayerView(controller: playback)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            Divider().padding(.top, 12)
            transcriptList
        }
        .onAppear { loadAudio() }
        .onChange(of: record.id) { _, _ in
            editingTitle = record.title
            loadAudio()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if titleEditing {
                    TextField("회의 제목", text: $editingTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.bold())
                    Button("저장") {
                        var copy = record
                        copy.title = editingTitle
                        onUpdate(copy)
                        titleEditing = false
                    }
                    Button("취소") {
                        editingTitle = record.title
                        titleEditing = false
                    }
                } else {
                    Text(record.title).font(.title3.bold())
                    Button {
                        titleEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Label(Self.dateFormatter.string(from: record.createdAt), systemImage: "calendar")
                Label("\(Int(record.durationSeconds))초", systemImage: "clock")
                Label("\(record.utterances.count) 발화", systemImage: "bubble.left.fill")
                Text(record.language.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
                if record.pdfFilePath != nil {
                    Label("\(record.pdfPageMarks.count) PDF 마크", systemImage: "doc.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if record.utterances.isEmpty {
                        Text("이 회의에는 저장된 발화가 없습니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    ForEach(Array(record.utterances.enumerated()), id: \.element.id) { _, utt in
                        utteranceRow(utt)
                            .id(utt.id)
                            .background(
                                isCurrent(utt)
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(12)
            }
            .onChange(of: playback.currentTime) { _, newTime in
                // 자동 스크롤: 재생 중 현재 발화로
                if playback.isPlaying,
                   let active = record.utterances.first(where: {
                       newTime >= $0.startSeconds && newTime < $0.endSeconds
                   }) {
                    withAnimation { proxy.scrollTo(active.id, anchor: .center) }
                }
            }
        }
    }

    private func utteranceRow(_ utt: Utterance) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                playback.seek(toSeconds: utt.startSeconds)
            } label: {
                Text(utt.timestampLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tint)
                    .frame(width: 48, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .help("이 시각으로 점프")

            Text(utt.speaker.label)
                .font(.caption.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(speakerColor(utt.speaker.id).opacity(0.2))
                .foregroundStyle(speakerColor(utt.speaker.id))
                .clipShape(Capsule())

            Text(utt.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            playback.seek(toSeconds: utt.startSeconds)
            if !playback.isPlaying { playback.play() }
        }
    }

    // MARK: - Helpers

    private func isCurrent(_ utt: Utterance) -> Bool {
        playback.currentTime >= utt.startSeconds && playback.currentTime < utt.endSeconds
    }

    private func loadAudio() {
        guard let path = record.audioFilePath else {
            playback.unload()
            return
        }
        playback.load(url: URL(fileURLWithPath: path))
    }

    private func speakerColor(_ id: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        let hash = abs(id.utf8.reduce(0) { Int($0) &+ Int($1) })
        return palette[hash % palette.count]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
