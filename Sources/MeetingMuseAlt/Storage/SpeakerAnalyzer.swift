import Foundation

/// 한 화자의 통계.
public struct SpeakerStat: Identifiable, Hashable, Sendable {
    public var speakerID: String
    public var label: String
    /// 누적 발화 시간 (초)
    public var totalSeconds: Double
    /// 발화 횟수
    public var utteranceCount: Int
    /// 전체 발화 시간 대비 비율 (0.0 ~ 1.0)
    public var fraction: Double

    public var id: String { speakerID }

    /// 평균 발화 길이 (초). 발화 0 이면 0.
    public var averageUtteranceSeconds: Double {
        utteranceCount > 0 ? totalSeconds / Double(utteranceCount) : 0
    }
}

/// 회의 전체 요약 지표.
public struct MeetingAnalytics: Sendable, Hashable {
    public var totalUtterances: Int
    public var totalSeconds: Double
    public var distinctSpeakers: Int
    public var speakers: [SpeakerStat]

    public static let empty = MeetingAnalytics(
        totalUtterances: 0,
        totalSeconds: 0,
        distinctSpeakers: 0,
        speakers: []
    )
}

/// `[Utterance]` 에서 화자별 통계를 계산.
///
/// 순수 함수 — 외부 의존성 0. 회의 영구 저장 / 검색 / 익스포트 어디서나 사용 가능.
public enum SpeakerAnalyzer {
    /// 누적 통계 계산. 같은 발화자가 여러 segment 에 나오면 합산하며
    /// 비율은 전체 시간 대비. `fraction` 내림차순으로 정렬해 반환.
    public static func analyze(_ utterances: [Utterance]) -> MeetingAnalytics {
        guard !utterances.isEmpty else { return .empty }

        var accumulatedSeconds: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var labels: [String: String] = [:]
        var total: Double = 0

        for u in utterances {
            let dur = max(0, u.endSeconds - u.startSeconds)
            accumulatedSeconds[u.speaker.id, default: 0] += dur
            counts[u.speaker.id, default: 0] += 1
            if labels[u.speaker.id] == nil {
                labels[u.speaker.id] = u.speaker.label
            }
            total += dur
        }

        let stats: [SpeakerStat] = accumulatedSeconds.map { (sid, secs) in
            SpeakerStat(
                speakerID: sid,
                label: labels[sid] ?? sid,
                totalSeconds: secs,
                utteranceCount: counts[sid] ?? 0,
                fraction: total > 0 ? secs / total : 0
            )
        }
        .sorted { $0.fraction > $1.fraction }

        return MeetingAnalytics(
            totalUtterances: utterances.count,
            totalSeconds: total,
            distinctSpeakers: stats.count,
            speakers: stats
        )
    }

    /// 회의 다양성 지수 (0 ~ 1): 가장 많이 발화한 화자의 점유율의 보수.
    /// 1.0 = 모든 화자가 균등 발화, 0.0 = 한 명만 발화.
    public static func diversityIndex(_ stats: [SpeakerStat]) -> Double {
        guard stats.count > 1, let top = stats.first else { return 0 }
        return 1.0 - top.fraction
    }

    /// 발화 시간 포맷 — `1분 23초` / `45초` / `1시간 5분`.
    public static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)시간 \(m)분" }
        if m > 0 { return "\(m)분 \(s)초" }
        return "\(s)초"
    }
}
