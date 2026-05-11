import SwiftUI

public enum ContentSection: String, CaseIterable, Identifiable, Hashable {
    case record
    case slides
    case search
    case library
    case settings

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .record:   return "녹음"
        case .slides:   return "발표 자료"
        case .search:   return "검색"
        case .library:  return "라이브러리"
        case .settings: return "설정"
        }
    }

    public var icon: String {
        switch self {
        case .record:   return "waveform"
        case .slides:   return "doc.fill"
        case .search:   return "magnifyingglass"
        case .library:  return "books.vertical.fill"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var vm: RecordingViewModel
    @EnvironmentObject private var detector: MeetingAppDetector
    @EnvironmentObject private var settings: AppSettings

    @State private var selection: ContentSection = .record
    @State private var repository: MeetingRepository = MeetingRepository(persistence: .shared)
    @State private var librarySnapshot: [MeetingRecord] = []
    @State private var saveBanner: String?

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
        List(selection: $selection) {
            Section("탭") {
                ForEach(ContentSection.allCases) { section in
                    Label(section.label, systemImage: section.icon).tag(section)
                }
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

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let banner = saveBanner {
                Text(banner)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.15))
            }
            sectionContent
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
            Text("· \(selection.label)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            if vm.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(vm.formattedElapsed)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .record:   recordSection
        case .slides:
            PdfSyncPanel(store: vm.pdfSyncStore, currentRecordingTime: { vm.elapsedSeconds })
        case .search:
            MeetingSearchView(repository: repository)
                .onAppear { reloadLibrary() }
        case .library:  librarySection
        case .settings: settingsSection
        }
    }

    private var recordSection: some View {
        VStack(spacing: 0) {
            if vm.utterances.isEmpty && !vm.isRecording {
                emptyState
            } else {
                transcriptList
            }
        }
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
                        UtteranceRow(utterance: utt).id(utt.id)
                    }
                    if vm.isProcessing {
                        ProgressView("정리 중...").padding()
                    }
                }
                .padding(20)
            }
            .onChange(of: vm.utterances.count) { _, _ in
                if let last = vm.utterances.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var librarySection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("저장된 회의 \(librarySnapshot.count)건")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("새로고침") { reloadLibrary() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            if librarySnapshot.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("저장된 회의가 없습니다")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(librarySnapshot) { rec in
                            libraryRow(rec)
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear { reloadLibrary() }
    }

    private func libraryRow(_ rec: MeetingRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title).font(.headline)
                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: rec.createdAt))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("⏱ \(Int(rec.durationSeconds))s")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("\(rec.utterances.count) 발화")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if rec.pdfFilePath != nil {
                        Image(systemName: "doc.fill").foregroundStyle(.tint)
                    }
                }
            }
            Spacer()
            Button {
                exportHTML(rec)
            } label: {
                Label("HTML 익스포트", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                try? repository.delete(rec)
                reloadLibrary()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var settingsSection: some View {
        Form {
            Section("테마") {
                Picker("색상 모드", selection: $settings.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.localizedLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("정보") {
                LabeledContent("앱 버전", value: "0.3.0")
                LabeledContent("저장 위치", value: "~/Library/Application Support/MeetingMuseAlt/")
                    .font(.caption.monospaced())
            }
        }
        .formStyle(.grouped)
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

            if !vm.utterances.isEmpty && !vm.isRecording {
                Button {
                    saveMeeting()
                } label: {
                    Label("회의 저장", systemImage: "tray.and.arrow.down.fill")
                }
            }
            if !vm.utterances.isEmpty {
                Button("초기화", role: .destructive) { vm.reset() }
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

    // MARK: - Actions

    private func saveMeeting() {
        do {
            let saved = try vm.saveCurrentMeeting(repository: repository)
            saveBanner = "저장 완료: \(saved.title)"
            reloadLibrary()
            // 3초 후 자동으로 배너 사라짐
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if saveBanner?.contains(saved.title) == true {
                    saveBanner = nil
                }
            }
        } catch {
            vm.errorAlert = ErrorAlert(title: "저장 실패", message: error.localizedDescription)
        }
    }

    private func reloadLibrary() {
        librarySnapshot = (try? repository.all()) ?? []
    }

    private func exportHTML(_ rec: MeetingRecord) {
        let exporter = MeetingExporter()
        let data = MeetingExportData(
            title: rec.title,
            createdAt: rec.createdAt,
            durationSeconds: rec.durationSeconds,
            language: rec.language,
            summary: rec.summary,
            utterances: rec.utterances
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(rec.title).html"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try exporter.write(data, to: url, as: .html)
                saveBanner = "익스포트 완료: \(url.lastPathComponent)"
            } catch {
                vm.errorAlert = ErrorAlert(title: "익스포트 실패", message: error.localizedDescription)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private struct UtteranceRow: View {
    let utterance: Utterance

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(speakerColor)
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
