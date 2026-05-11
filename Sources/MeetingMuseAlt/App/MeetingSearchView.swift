import SwiftUI

/// 회의 라이브러리 전문 검색 패널.
///
/// `MeetingRepository`에서 회의 목록을 불러오고, `MeetingSearchEngine`으로
/// 필터링한 결과를 표시한다. 발화 매치는 첫 매치 텍스트를 미리보기로 보여준다.
@MainActor
public struct MeetingSearchView: View {
    @State private var queryText: String = ""
    @State private var speakerFilter: String = ""
    @State private var records: [MeetingRecord] = []
    @State private var hits: [MeetingSearchHit] = []
    @State private var isLoading = false

    private let repository: MeetingRepository
    private let engine = MeetingSearchEngine()

    public init(repository: MeetingRepository) {
        self.repository = repository
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .task { await loadAll() }
        .onChange(of: queryText) { _, _ in performSearch() }
        .onChange(of: speakerFilter) { _, _ in performSearch() }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("회의/발화 검색", text: $queryText)
                .textFieldStyle(.plain)
                .font(.body)
            Divider().frame(height: 18)
            TextField("화자 ID 필터 (예: A)", text: $speakerFilter)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 140)
            if !queryText.isEmpty || !speakerFilter.isEmpty {
                Button {
                    queryText = ""
                    speakerFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var resultsList: some View {
        if isLoading {
            ProgressView("불러오는 중...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hits.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hits) { hit in
                        hitRow(hit)
                        Divider()
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func hitRow(_ hit: MeetingSearchHit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(hit.record.title)
                    .font(.headline)
                if hit.titleMatched {
                    Text("• 제목 일치")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(Self.dateFormatter.string(from: hit.record.createdAt))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if hit.summaryMatched, let s = hit.record.summary {
                Text("요약: \(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !hit.utteranceHits.isEmpty {
                ForEach(hit.utteranceHits.prefix(3), id: \.utteranceIndex) { uh in
                    HStack(alignment: .top, spacing: 8) {
                        Text(uh.utterance.timestampLabel)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        Text("[\(uh.utterance.speaker.label)] \(uh.utterance.text)")
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
                if hit.utteranceHits.count > 3 {
                    Text("…및 \(hit.utteranceHits.count - 3)건 더")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(records.isEmpty ? "저장된 회의가 없습니다" : "검색 결과 없음")
                .font(.title3)
            if records.isEmpty {
                Text("회의를 녹음하고 저장하면 여기에서 검색할 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        // `repository.all()` 은 throws 시그니처지만 현재 JSON 백엔드에서는
        // 실제로 던지지 않으므로 try? 로 폴백 처리.
        self.records = (try? repository.all()) ?? []
        performSearch()
    }

    private func performSearch() {
        let speakerID = speakerFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = MeetingSearchQuery(
            text: queryText,
            speakerID: speakerID.isEmpty ? nil : speakerID
        )
        if q.isEmpty {
            // 비어있을 때는 전체 회의 (매치 정보 없이)
            hits = records.map { MeetingSearchHit(record: $0) }
        } else {
            hits = engine.search(records, query: q)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
