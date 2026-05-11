import Foundation

/// `MeetingRecord` CRUD facade.
///
/// 현재 구현은 `MeetingPersistence`의 인메모리 캐시 + JSON 파일을 통과합니다.
/// 호출자는 저장소 구현체에 무관하게 동일한 API를 사용합니다.
@MainActor
public final class MeetingRepository {
    private let persistence: MeetingPersistence

    public init(persistence: MeetingPersistence) {
        self.persistence = persistence
    }

    /// 기본 온디스크 저장소를 사용하는 편의 이니셜라이저.
    public convenience init() {
        self.init(persistence: .shared)
    }

    // MARK: - Create

    /// 새 회의를 저장하고 생성된 레코드를 반환합니다.
    @discardableResult
    public func save(
        title: String,
        utterances: [Utterance],
        durationSeconds: Double,
        audioFileURL: URL? = nil,
        language: String = "ko",
        summary: String? = nil,
        createdAt: Date = Date()
    ) throws -> MeetingRecord {
        let record = MeetingRecord(
            title: title,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFileURL?.path,
            utterances: utterances,
            language: language,
            summary: summary
        )
        try persistence.upsert(record)
        return record
    }

    // MARK: - Read

    /// `createdAt` 내림차순 (최신순) 으로 정렬된 모든 회의.
    public func all() throws -> [MeetingRecord] {
        persistence.snapshot().sorted { $0.createdAt > $1.createdAt }
    }

    /// id로 단건 조회.
    public func find(id: UUID) throws -> MeetingRecord? {
        persistence.find(id: id)
    }

    // MARK: - Update

    /// 호출자가 수정한 레코드를 영속 저장소에 반영합니다.
    /// (값 타입이므로 mutating local var → repo.update(local) 패턴)
    public func update(_ record: MeetingRecord) throws {
        try persistence.upsert(record)
    }

    // MARK: - Delete

    public func delete(_ record: MeetingRecord) throws {
        try persistence.remove(id: record.id)
    }

    public func deleteAll() throws {
        for r in persistence.snapshot() {
            try persistence.remove(id: r.id)
        }
    }
}
