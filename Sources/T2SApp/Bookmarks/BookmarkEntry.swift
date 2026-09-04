import Foundation
import T2SCore

/// One saved bookmark, resolved for display (spec §2.2 "Bookmarks"): where it is, what it says,
/// and when in the audio it falls. `position` is kept so the jump can resolve it against the
/// timeline the coordinator actually holds.
public struct BookmarkEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let position: Position
    public let chapterTitle: String
    public let snippet: String
    /// Seconds at 1x from the document start.
    public let timeSeconds: TimeInterval
    public let createdAt: Date

    public init(id: UUID, position: Position, chapterTitle: String, snippet: String,
                timeSeconds: TimeInterval, createdAt: Date) {
        self.id = id
        self.position = position
        self.chapterTitle = chapterTitle
        self.snippet = snippet
        self.timeSeconds = timeSeconds
        self.createdAt = createdAt
    }

    public var timeText: String { DurationFormatter.clock(timeSeconds) }
}

/// The text shown for a bookmark: the utterance's source from the bookmark's offset, cut at a
/// word boundary so a row never ends mid-word.
public enum BookmarkSnippet {
    /// UTF-16 units, the unit every offset in `Position` uses.
    public static let maxLength = 90

    public static func make(from source: String, offset: Int) -> String {
        let units = Array(source.utf16)
        let start = max(0, min(offset, units.count))
        guard start < units.count else { return "" }
        let rest = units[start...]
        if rest.count <= maxLength { return String(decoding: rest, as: UTF16.self) }
        // Room for the ellipsis, then back up to the last space so no word is cut.
        let window = rest.prefix(maxLength - 1)
        let space = UInt16(UnicodeScalar(" ").value)
        let cut = window.lastIndex(of: space).map { window[..<$0] } ?? window
        var text = String(decoding: cut, as: UTF16.self)
        while text.hasSuffix(" ") { text.removeLast() }
        return text + "…"
    }
}
