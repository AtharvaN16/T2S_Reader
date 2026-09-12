import Foundation
import T2SCore

/// One saved bookmark, resolved for display (spec §2.2 "Bookmarks"): where it is, what it says, and
/// the span of audio it covers. `position` is kept so the jump can resolve it against the timeline
/// the coordinator actually holds.
///
/// The book's words lead and the reader's note follows them, quoted against a rule — ``lead`` and
/// ``note`` are that arrangement, in one place, so every surface showing a bookmark shows it the
/// same way. It was the other way about until 2026-09-12, on the 2026-09-11 spec §6 reading that a
/// list of one's own words is a notebook rather than a second copy of the book. The owner's call
/// reverses it: "the bookmark is the main focus". A note is a gloss on a passage, and a gloss reads
/// under the thing it glosses.
public struct BookmarkEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let position: Position
    public let chapterTitle: String
    /// The book's words at the bookmark, trimmed for a row.
    public let passage: String
    /// The same words untrimmed, for a screen with room to print them — the note editor shows the
    /// whole of what is being annotated (owner, 2026-09-12). Falls back to `passage`.
    public let fullPassage: String
    /// The reader's own note, nil or blank when they have written none.
    public let userNote: String?
    /// Seconds at 1x from the document start.
    public let timeSeconds: TimeInterval
    /// Where the bookmarked utterance ends, so a row can show a span rather than an instant.
    public let endSeconds: TimeInterval
    public let createdAt: Date

    public init(id: UUID, position: Position, chapterTitle: String, passage: String, fullPassage: String? = nil,
                userNote: String?, timeSeconds: TimeInterval, endSeconds: TimeInterval, createdAt: Date) {
        self.id = id
        self.position = position
        self.chapterTitle = chapterTitle
        self.passage = passage
        self.fullPassage = fullPassage ?? passage
        self.userNote = userNote
        self.timeSeconds = timeSeconds
        self.endSeconds = endSeconds
        self.createdAt = createdAt
    }

    /// A note of only whitespace is no note.
    private var writtenNote: String? {
        guard let userNote, !userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return userNote
    }

    public var hasNote: Bool { writtenNote != nil }
    /// What a bookmark says first: the book's words, always. A bookmark is a place in a book before
    /// it is anything of the reader's.
    public var lead: String { passage }
    /// The reader's own words, to stand under the passage; nil when they wrote none.
    public var note: String? { writtenNote }

    public var timeText: String { DurationFormatter.clock(timeSeconds) }
    public var rangeText: String { "\(DurationFormatter.clock(timeSeconds)) – \(DurationFormatter.clock(endSeconds))" }
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
