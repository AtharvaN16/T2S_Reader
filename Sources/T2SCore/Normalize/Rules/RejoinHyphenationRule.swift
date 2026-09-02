/// Rule 1 (spec §4.1): "con-\ntinent" → "continent". Real hyphens have no line break and are kept.
public struct RejoinHyphenationRule: NormalizerRule {
    static let pattern = Pattern("(\\p{L})-[ \\t]*\\r?\\n[ \\t]*(\\p{L})")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.pattern, template: "$1$2")
        return t
    }
}
