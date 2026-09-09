import Foundation

/// The chapter row's label (owner's rule, 2026-09-09): a title that starts with a number keeps it
/// as "Chp 7: A Precarious Position"; one that is only a number, or empty, is "Chapter 7" in full;
/// one with a name but no number takes the chapter's ordinal, "Chp 3: The Fall"; and a title that
/// already names itself ("Chapter 7", "Part Two", "Prologue") is left as the book wrote it.
public enum ChapterLabel {
    public static func text(for title: String, ordinal: Int) -> String {
        // Built per call: `Regex` is not `Sendable`, so a static would not pass strict concurrency,
        // and a chapter row asks once per redraw, which is nothing.
        let numbered = /^(\d+)\s*[.:)\-–—]?\s*(.*)$/
        let selfNamed = /^(?i:chapter|chp|ch\.|part|book|prologue|epilogue|introduction|preface|foreword|afterword|appendix)\b/
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: numbered) {
            let name = match.2.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Chapter \(match.1)" : "Chp \(match.1): \(name)"
        }
        if trimmed.isEmpty { return "Chapter \(ordinal)" }
        if trimmed.prefixMatch(of: selfNamed) != nil { return trimmed }
        return "Chp \(ordinal): \(trimmed)"
    }
}
