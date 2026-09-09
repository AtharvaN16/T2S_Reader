import Foundation

/// Rule 6 (spec §4.1): applied last, immediately before G2P. Whole-word matches only.
///
/// One alternation over every entry, one pass over the text (Plan 16 — the rule used to run one
/// pass per entry). The pass sees the reader's text, not another entry's replacement, and where
/// two terms overlap the one that starts first wins, then the one listed first.
public struct PronunciationDictionaryRule: NormalizerRule {
    private let pattern: Pattern?
    private let replacements: [String]

    public init(entries: [PronunciationEntry]) {
        // An empty term would match the empty string at every boundary; it is not a term.
        let entries = entries.filter { !$0.term.isEmpty }
        replacements = entries.map(\.replacement)
        guard !entries.isEmpty else { pattern = nil; return }
        let alternatives = entries.map { e -> String in
            // The hyphen rule has already run: "commander-in-chief" in the text is "commander in chief".
            let escaped = NSRegularExpression.escapedPattern(for: SplitHyphenatedCompoundsRule.spokenForm(of: e.term))
            return e.caseSensitive ? "(\(escaped))" : "((?i:\(escaped)))"
        }
        // Lookarounds rather than \b: a term ending in a non-word character ("C++") has no
        // word boundary after it, so \b would never match.
        pattern = Pattern("(?<![\\p{L}\\p{N}_])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])")
    }

    public func apply(_ input: NormalizedText) -> NormalizedText {
        guard let pattern else { return input }
        var t = input
        t.replaceMatches(of: pattern) { m, _ in
            (1..<m.numberOfRanges).first { m.range(at: $0).location != NSNotFound }.map { replacements[$0 - 1] }
        }
        return t
    }
}
