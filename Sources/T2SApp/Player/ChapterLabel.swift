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
}
