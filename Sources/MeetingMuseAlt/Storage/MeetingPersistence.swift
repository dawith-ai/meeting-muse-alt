import Foundation

/// 파일 기반 영속화 스택. `~/Library/Application Support/MeetingMuseAlt/meetings.json`
/// 에 `[MeetingRecord]` 전체를 직렬화합니다.
///
/// 향후 SwiftData/GRDB로 갈아끼울 때 `Repository` API만 유지하면 됩니다.
@MainActor
public final class MeetingPersistence {
    /// 프로세스 전역 인스턴스 (온디스크).
    public static let shared: MeetingPersistence = {
        do {
            return try MeetingPersistence(inMemory: false)
        } catch {
            print("[MeetingPersistence] 온디스크 초기화 실패 (\(error)) — 인메모리 폴백")
            return MeetingPersistence(inMemoryFallback: ())
        }
    }()

    /// `nil`이면 인메모리, 아니면 온디스크 JSON 파일 경로.
    public let storeURL: URL?
    private var records: [MeetingRecord]

    public init(inMemory: Bool) throws {
        if inMemory {
            self.storeURL = nil
            self.records = []
        } else {
            let url = try Self.defaultStoreURL()
            self.storeURL = url
            self.records = try Self.loadRecords(from: url)
        }
    }

    /// 온디스크 초기화 실패 시 `shared`가 호출하는 폴백.
    private init(inMemoryFallback: Void) {
        self.storeURL = nil
        self.records = []
    }

    // MARK: - In-memory ops (Repository에서 호출)

    func snapshot() -> [MeetingRecord] { records }

    func upsert(_ record: MeetingRecord) throws {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        try flush()
    }

    func remove(id: UUID) throws {
        records.removeAll { $0.id == id }
        try flush()
    }

    func find(id: UUID) -> MeetingRecord? {
        records.first { $0.id == id }
    }

    // MARK: - File IO

    private func flush() throws {
        guard let url = storeURL else { return }
        let data = try Self.encoder.encode(records)
        try data.write(to: url, options: [.atomic])
    }

    private static func loadRecords(from url: URL) throws -> [MeetingRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        do {
            return try decoder.decode([MeetingRecord].self, from: data)
        } catch {
            // 스키마 드리프트 등으로 디코딩 실패 시 빈 목록으로 폴백.
            print("[MeetingPersistence] 디코딩 실패 (\(error)) — 빈 라이브러리로 시작")
            return []
        }
    }

    private static func defaultStoreURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("MeetingMuseAlt", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("meetings.json", isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
