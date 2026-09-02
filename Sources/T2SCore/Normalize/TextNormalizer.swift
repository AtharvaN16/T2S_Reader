/// Composes the rules in the order fixed by spec §4.1.
public struct TextNormalizer: Sendable {
    public static let version = Versions.normalizer
    public private(set) var rules: [any NormalizerRule]

    public init(dictionary: [PronunciationEntry] = []) {
        rules = [
            RejoinHyphenationRule(),
            StripCitationsRule(),
            ExpandAbbreviationsRule(),
            CollapseURLsRule(),          // before numbers: a URL with digits must survive intact
            ExpandNumbersRule(),
            CollapseWhitespaceRule(),
            PronunciationDictionaryRule(entries: dictionary),
        ]
    }

    public func normalize(_ source: String) -> NormalizedText {
        rules.reduce(NormalizedText(source: source)) { $1.apply($0) }
    }
}
