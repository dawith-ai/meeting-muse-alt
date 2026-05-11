import Foundation

public struct Speaker: Hashable, Identifiable, Codable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String? = nil) {
        self.id = id
        self.label = label ?? id
    }

    public static let unknown = Speaker(id: "?", label: "?")
}
