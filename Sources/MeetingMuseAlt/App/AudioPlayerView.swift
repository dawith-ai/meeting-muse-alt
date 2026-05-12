import SwiftUI

/// 회의 녹음 재생 컨트롤 — 재생/정지 + 진행바 + 시각/총 길이 + 시크.
@MainActor
public struct AudioPlayerView: View {
    @ObservedObject var controller: AudioPlaybackController
    public init(controller: AudioPlaybackController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    controller.togglePlay()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.borderless)
                .disabled(controller.fileURL == nil)

                VStack(alignment: .leading, spacing: 2) {
                    if let url = controller.fileURL {
                        Text(url.lastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("로드된 오디오 없음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let err = controller.errorMessage {
                        Text(err).font(.caption2).foregroundStyle(.red)
                    }
                }
                Spacer()
                Text("\(AudioPlaybackController.formatTime(controller.currentTime)) / \(AudioPlaybackController.formatTime(controller.duration))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding<Double>(
                    get: { controller.currentTime },
                    set: { controller.seek(toSeconds: $0) }
                ),
                in: 0...max(0.1, controller.duration)
            )
            .disabled(controller.fileURL == nil)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }
}
