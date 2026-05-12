import Foundation

/// 사용자가 회의 중/후 작성하는 자유 메모.
///
/// `MeetingRecord` 와 별도로 즉시 영속 저장하고 싶을 때 사용 — 작은 노트 단위로
/// 다수를 보유 가능 (예: 회의 종료 후에도 추가 메모 작성).
public struct MeetingNote: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var meetingID: UUID?
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        meetingID: UUID? = nil,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.meetingID = meetingID
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// `MeetingNote` 영구 저장. JSON 파일 (`notes.json`).
@MainActor
public final class MeetingNotesStore: ObservableObject {
    @Published public private(set) var notes: [MeetingNote] = []

    public let storeURL: URL?

    public init(inMemory: Bool = false) {
        if inMemory {
            self.storeURL = nil
        } else {
            self.storeURL = (try? Self.defaultStoreURL()) ?? nil
            self.notes = Self.load(from: storeURL)
        }
    }

    @discardableResult
    public func add(_ text: String, meetingID: UUID? = nil) -> MeetingNote {
        let n = MeetingNote(meetingID: meetingID, text: text)
        notes.insert(n, at: 0)
        try? flush()
        return n
    }

    public func update(id: UUID, text: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].text = text
        notes[idx].updatedAt = Date()
        try? flush()
    }

    public func remove(id: UUID) {
        notes.removeAll { $0.id == id }
        try? flush()
    }

    public func clear() {
        notes.removeAll()
        try? flush()
    }

    public func notes(forMeeting meetingID: UUID?) -> [MeetingNote] {
        notes.filter { $0.meetingID == meetingID }
    }

    // MARK: - File IO

    private func flush() throws {
        guard let url = storeURL else { return }
        let data = try Self.encoder.encode(notes)
        try data.write(to: url, options: [.atomic])
    }

    private static func load(from url: URL?) -> [MeetingNote] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return [] }
            return try decoder.decode([MeetingNote].self, from: data)
        } catch {
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
        return dir.appendingPathComponent("notes.json", isDirectory: false)
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
