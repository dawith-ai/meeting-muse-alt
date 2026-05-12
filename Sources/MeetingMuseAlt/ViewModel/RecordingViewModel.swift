import Foundation
import SwiftUI
import Combine

public struct ErrorAlert: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
}

@MainActor
public final class RecordingViewModel: ObservableObject {
    @Published public private(set) var utterances: [Utterance] = []
    @Published public private(set) var isRecording = false
    @Published public private(set) var isProcessing = false
    @Published public private(set) var elapsedSeconds: Double = 0
    @Published public var includeSystemAudio = false
    @Published public var errorAlert: ErrorAlert?
    @Published public private(set) var currentRecording: AudioRecording?
    @Published public private(set) var summaryMarkdown: String?
    @Published public private(set) var isSummarizing = false

    public let pdfSyncStore = PdfSyncStore()

    private let recorder: AudioRecorder
    private let transcriber: TranscriptionService
    private var timerTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?

    public init(
        recorder: AudioRecorder = AudioRecorder(),
        transcriber: TranscriptionService = WhisperEngine()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    public var formattedElapsed: String {
        let total = Int(elapsedSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    public func toggleRecording() async {
        if isRecording {
            await stop()
        } else {
            await start()
        }
    }

    public func reset() {
        utterances = []
        elapsedSeconds = 0
        currentRecording = nil
        summaryMarkdown = nil
        pdfSyncStore.clearMarks()
    }

    /// `OpenAISummarizer` 호출. API 키 미입력 시 던지지 않고 `summaryMarkdown` 만 nil 유지.
    public func generateSummary(apiKey: String, languageHint: String = "ko") async {
        guard !utterances.isEmpty else { return }
        guard !apiKey.isEmpty else {
            errorAlert = ErrorAlert(title: "API 키 필요", message: "설정에서 OpenAI API 키를 입력해주세요.")
            return
        }
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            let summarizer = OpenAISummarizer(apiKey: apiKey)
            let md = try await summarizer.summarize(
                utterances: utterances,
                title: nil,
                languageHint: languageHint
            )
            summaryMarkdown = md
        } catch {
            errorAlert = ErrorAlert(title: "요약 실패", message: error.localizedDescription)
        }
    }

    /// 현재 회의를 영구 저장소에 저장합니다.
    ///
    /// 마지막 녹음과 누적 발화, 그리고 PDF 동기화 마크까지 함께 직렬화합니다.
    @discardableResult
    public func saveCurrentMeeting(
        repository: MeetingRepository,
        title: String? = nil
    ) throws -> MeetingRecord {
        let resolvedTitle = title ?? Self.defaultTitle()
        let snapshot = pdfSyncStore.snapshot()
        var record = try repository.save(
            title: resolvedTitle,
            utterances: utterances,
            durationSeconds: elapsedSeconds,
            audioFileURL: currentRecording?.fileURL,
            language: "ko",
            summary: nil
        )
        // PDF 상태가 있으면 같은 레코드에 덧붙여 업데이트.
        if snapshot.pdfURL != nil || !snapshot.marks.isEmpty {
            record.pdfFilePath = snapshot.pdfURL?.path
            record.pdfPageMarks = snapshot.marks
            try repository.update(record)
        }
        return record
    }

    private static func defaultTitle() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko")
        f.dateFormat = "yyyy-MM-dd HH:mm 회의"
        return f.string(from: Date())
    }

    private func start() async {
        do {
            try await recorder.start(includeSystemAudio: includeSystemAudio)
            isRecording = true
            startTimer()
            startLiveTranscription()
        } catch {
            errorAlert = ErrorAlert(
                title: "녹음 실패",
                message: error.localizedDescription
            )
        }
    }

    private func stop() async {
        stopTimer()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        isRecording = false
        isProcessing = true
        defer { isProcessing = false }

        do {
            let recording = try await recorder.stop()
            currentRecording = recording
            let final = try await transcriber.transcribe(audioURL: recording.fileURL)
            utterances = final
        } catch {
            errorAlert = ErrorAlert(
                title: "처리 실패",
                message: error.localizedDescription
            )
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.elapsedSeconds += 1
                if let pdfStore = self?.pdfSyncStore, let elapsed = self?.elapsedSeconds {
                    pdfStore.tick(timeSeconds: elapsed)
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func startLiveTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = self.transcriber.liveTranscriptionStream(from: self.recorder.liveAudioStream)
            for await partial in stream {
                if Task.isCancelled { break }
                self.applyPartial(partial)
            }
        }
    }

    private func applyPartial(_ utt: Utterance) {
        utterances.append(utt)
    }
}

