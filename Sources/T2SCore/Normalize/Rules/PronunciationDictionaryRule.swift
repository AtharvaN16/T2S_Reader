import Foundation

/// Rule 6 (spec §4.1): applied last, immediately before G2P. Whole-word matches only.
public struct PronunciationDictionaryRule: NormalizerRule {
    private let compiled: [(Pattern, String)]

    public init(entries: [PronunciationEntry]) {
        // Lookarounds rather than \b: a term ending in a non-word character ("C++") has no
        // word boundary after it, so \b would never match.
        compiled = entries.map { e in
            let escaped = NSRegularExpression.escapedPattern(for: e.term)
            let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            return (Pattern(pattern, e.caseSensitive ? [] : [.caseInsensitive]), e.replacement)
        }
    }

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        for (pattern, replacement) in compiled {
            t.replaceMatches(of: pattern) { _, _ in replacement }
        }
        return t
    }
}
