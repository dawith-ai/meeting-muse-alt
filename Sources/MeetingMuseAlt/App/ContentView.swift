import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var vm: RecordingViewModel
    @EnvironmentObject private var detector: MeetingAppDetector

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .alert(item: $vm.errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("확인")))
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section("녹음") {
                Label("새 회의", systemImage: "waveform")
            }
            Section("자동 감지") {
                if detector.detectedApps.isEmpty {
                    Text("실행 중인 회의 앱 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detector.detectedApps, id: \.bundleIdentifier) { app in
                        Label(app.displayName, systemImage: "video")
                            .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if vm.utterances.isEmpty && !vm.isRecording {
                emptyState
            } else {
                transcriptList
            }

            Divider()

            controlBar
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text("Meeting Muse — Alt")
                .font(.title2.bold())
            Spacer()
            if vm.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(vm.formattedElapsed)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("회의 녹음을 시작하세요")
                .font(.title3)
            Text("'녹음 시작' 버튼을 누르거나, 줌·구글 미트가 시작되면 자동으로 감지됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(vm.utterances.enumerated()), id: \.element.id) { _, utt in
                        UtteranceRow(utterance: utt)
                            .id(utt.id)
                    }
                    if vm.isProcessing {
                        ProgressView("정리 중...")
                            .padding()
                    }
                }
                .padding(20)
            }
            .onChange(of: vm.utterances.count) { _, _ in
                if let last = vm.utterances.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            Button {
                Task { await vm.toggleRecording() }
            } label: {
                Label(
                    vm.isRecording ? "정지" : "녹음 시작",
                    systemImage: vm.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.body.bold())
            }
            .keyboardShortcut(.space, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .tint(vm.isRecording ? .red : .accentColor)

            if !vm.utterances.isEmpty {
                Button("초기화", role: .destructive) {
                    vm.reset()
                }
                .disabled(vm.isRecording)
            }

            Spacer()

            Toggle("시스템 오디오 함께 녹음", isOn: $vm.includeSystemAudio)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(vm.isRecording)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct UtteranceRow: View {
    let utterance: Utterance

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(speakerColor)
                Text(utterance.speaker.label)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(utterance.timestampLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(utterance.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var speakerColor: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal]
        let idx = abs(utterance.speaker.id.hashValue) % palette.count
        return palette[idx]
    }
}
