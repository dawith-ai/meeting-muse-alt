import SwiftUI

/// 회의 화자별 통계 패널.
public struct SpeakerAnalyticsView: View {
    public let utterances: [Utterance]

    public init(utterances: [Utterance]) {
        self.utterances = utterances
    }

    public var body: some View {
        let analytics = SpeakerAnalyzer.analyze(utterances)
        if analytics.totalUtterances == 0 {
            emptyState
        } else {
            content(analytics)
        }
    }

    private func content(_ a: MeetingAnalytics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statCards(a)
                Divider()
                speakerList(a)
            }
            .padding(16)
        }
    }

    private func statCards(_ a: MeetingAnalytics) -> some View {
        HStack(spacing: 12) {
            statCard(icon: "person.2.fill", label: "참여 화자", value: "\(a.distinctSpeakers)명")
            statCard(icon: "bubble.left.fill", label: "총 발언", value: "\(a.totalUtterances)회")
            statCard(icon: "clock.fill", label: "총 시간", value: SpeakerAnalyzer.formatDuration(a.totalSeconds))
            statCard(
                icon: "chart.pie.fill",
                label: "다양성",
                value: String(format: "%.0f%%", SpeakerAnalyzer.diversityIndex(a.speakers) * 100)
            )
        }
    }

    private func statCard(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func speakerList(_ a: MeetingAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundStyle(.tint)
                Text("발언 비중").font(.headline)
            }
            ForEach(a.speakers) { s in
                speakerRow(s)
            }
        }
    }

    private func speakerRow(_ s: SpeakerStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color(for: s.speakerID)).frame(width: 12, height: 12)
                Text(s.label).font(.body.bold())
                Spacer()
                Text(String(format: "%.0f%%", s.fraction * 100))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(s.utteranceCount)회 · \(SpeakerAnalyzer.formatDuration(s.totalSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("평균 \(String(format: "%.1f", s.averageUtteranceSeconds))초/발화")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: s.fraction)
                .progressViewStyle(.linear)
                .tint(color(for: s.speakerID))
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("분석할 발화가 없습니다")
                .font(.title3)
            Text("회의를 녹음하면 화자별 통계가 여기에 표시됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(for speakerID: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        let hash = abs(speakerID.utf8.reduce(0) { Int($0) &+ Int($1) })
        return palette[hash % palette.count]
    }
}
