import Foundation

/// The chapter row's label (owner's rule, 2026-09-09): a title that starts with a number keeps it
/// as "Chp 7: A Precarious Position"; one that is only a number, or empty, is "Chapter 7" in full;
/// anything else ("Title Page", "Introduction", "Part Two") is left as the book wrote it — front
/// matter is not a chapter, so it never gets a made-up number.
public enum ChapterLabel {
    public static func text(for title: String, ordinal: Int) -> String {
        // Built per call: `Regex` is not `Sendable`, so a static would not pass strict concurrency,
        // and a chapter row asks once per redraw, which is nothing.
        let numbered = /^(\d+)\s*[.:)\-–—]?\s*(.*)$/
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: numbered) {
            let name = match.2.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Chapter \(match.1)" : "Chp \(match.1): \(name)"
        }
        return trimmed.isEmpty ? "Chapter \(ordinal)" : trimmed
    }

    /// Where the book proper starts (owner's ask, 2026-09-09): the first chapter whose title
    /// starts with a number, or reads "Chapter 1" / "Chapter One" / "Chapter I" in any case, with
    /// the chapter's number. Nil when no title does, and nil when the first chapter is already it —
    /// there is no front matter to skip then.
    public static func bodyStart(titles: [String]) -> (index: Int, number: Int)? {
        let numbered = /^(\d+)\b/
        let worded = /^(?:chapter|chp|ch)\.?\s+(\d+|one|i)\b/.ignoresCase()
        for (index, title) in titles.enumerated() {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let number: Int?
            if let match = trimmed.prefixMatch(of: numbered) {
                number = Int(match.1)
            } else if let match = trimmed.prefixMatch(of: worded) {
                number = Int(match.1) ?? 1                                  // "one", "i"
            } else {
                number = nil
            }
            if let number { return index > 0 ? (index, number) : nil }
        }
        return nil
    }
}
