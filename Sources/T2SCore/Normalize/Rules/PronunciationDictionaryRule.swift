import Foundation

/// Rule 6 (spec §4.1): applied last, immediately before G2P. Whole-word matches only.
public struct PronunciationDictionaryRule: NormalizerRule {
    private let compiled: [(Pattern, String)]

    public init(entries: [PronunciationEntry]) {
        compiled = entries.map { e in
            let escaped = NSRegularExpression.escapedPattern(for: e.term)
            return (Pattern("\\b\(escaped)\\b", e.caseSensitive ? [] : [.caseInsensitive]), e.replacement)
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
