import Foundation

public struct PronunciationEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var term: String
    public var replacement: String
    public var caseSensitive: Bool

    public init(id: UUID = UUID(), term: String, replacement: String, caseSensitive: Bool = false) {
        self.id = id
        self.term = term
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}
