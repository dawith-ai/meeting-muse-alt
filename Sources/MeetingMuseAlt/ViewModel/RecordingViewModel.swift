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
