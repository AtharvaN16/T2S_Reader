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
        let utf16Count = source.utf16.count
        let start = max(0, min(offset, utf16Count))
        guard start < utf16Count else { return "" }
        let startIndex = String.Index(utf16Offset: start, in: source)
        let rest = source[startIndex...]
        if rest.utf16.count <= maxLength { return String(rest) }

        // Room for the ellipsis. Cut on Character boundaries — never mid-surrogate-pair, never
        // mid-grapheme-cluster — by taking whole characters until the next one would overrun the
        // budget, then back up to the last space so no word is cut.
        var prefixEnd = rest.startIndex
        var utf16Used = 0
        for i in rest.indices {
            let length = rest[i].utf16.count
            if utf16Used + length > maxLength - 1 { break }
            utf16Used += length
            prefixEnd = rest.index(after: i)
        }
        let window = rest[..<prefixEnd]
        let cut = window.lastIndex(of: " ").map { window[..<$0] } ?? window
        var text = String(cut)
        while text.hasSuffix(" ") { text.removeLast() }
        return text + "…"
    }
}
