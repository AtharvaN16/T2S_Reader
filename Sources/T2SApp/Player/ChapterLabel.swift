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

    /// Where the book proper starts (owner's ask, 2026-09-09; widened 2026-09-10 after a book whose
    /// chapters carry no numbers at all showed no pill). Two readings, in order:
    ///
    /// 1. **A numbered heading**: a title that starts with a digit, or reads "Chapter 1" /
    ///    "Chapter One" / "Chapter I" / "Part One", or is a bare "One:" / "I." — the pill can then
    ///    name the number it skips to.
    /// 2. **The end of the front matter**: no numbered heading anywhere, but the book opens with
    ///    titles that are plainly not chapters ("Title Page", "Contents", "Introduction"…). The
    ///    first title after them is the body, and `number` is nil — the pill says "Skip the front
    ///    matter" rather than inventing a chapter number.
    ///
    /// Nil when the first chapter is already the body: there is nothing to skip then.
    public static func bodyStart(titles: [String]) -> (index: Int, number: Int?)? {
        if let numbered = firstNumberedChapter(in: titles) { return numbered }
        return firstChapterAfterFrontMatter(in: titles)
    }

    private static func firstNumberedChapter(in titles: [String]) -> (index: Int, number: Int?)? {
        let digits = /^(\d+)\b/
        // "Chapter 3", "Ch. 3", "Part One", "Section I" — the word, then the number.
        let worded = /^(?:chapter|chp|ch|part|section)\.?\s+(\d+|one|i)\b/.ignoresCase()
        // A bare "One: The Basics" or "I. Marley's Ghost": the number alone, and then punctuation,
        // which is what keeps "Once upon" and "Introduction" out.
        let bare = /^(one|i)\s*[.:)\-–—]/.ignoresCase()
        for (index, title) in titles.enumerated() {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let number: Int?
            if let match = trimmed.prefixMatch(of: digits) {
                number = Int(match.1)
            } else if let match = trimmed.prefixMatch(of: worded) {
                number = Int(match.1) ?? 1                                  // "one", "i"
            } else if trimmed.prefixMatch(of: bare) != nil {
                number = 1
            } else {
                number = nil
            }
            if let number { return index > 0 ? (index, number) : nil }
        }
        return nil
    }

    /// The titles a book puts before its first chapter. Matched whole (after trimming and any
    /// "Introduction: The Systems Lens" subtitle), so a chapter called "Contents of the Vault" is
    /// not mistaken for the table of contents. "Prologue" is deliberately absent: it is the story.
    private static let frontMatterTitles: Set<String> = [
        "cover", "half title", "half-title", "title page", "title", "copyright", "copyright page",
        "dedication", "epigraph", "contents", "table of contents", "toc", "foreword", "forward",
        "preface", "introduction", "author's note", "authors note", "a note on the text",
        "note to the reader", "acknowledgements", "acknowledgments", "praise", "reviews",
        "also by this author", "about the author", "frontmatter", "front matter", "maps", "map",
        "list of illustrations", "illustrations", "dramatis personae", "cast of characters",
    ]

    private static func firstChapterAfterFrontMatter(in titles: [String]) -> (index: Int, number: Int?)? {
        var index = 0
        while index < titles.count, isFrontMatter(titles[index]) { index += 1 }
        // Nothing skipped, or everything is front matter: no body to point at.
        guard index > 0, index < titles.count else { return nil }
        return (index, nil)
    }

    private static func isFrontMatter(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if frontMatterTitles.contains(trimmed) { return true }
        // "Introduction: The Systems Lens", "Preface — 2014": the head of the title is what names it.
        let head = trimmed.split(whereSeparator: { ":—–-".contains($0) }).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? trimmed
        return frontMatterTitles.contains(head)
    }
}
