/// Rule 3 (spec §4.1): "[14]" must never become "bracket fourteen".
public struct StripCitationsRule: NormalizerRule {
    static let bracketed = Pattern(" ?\\[\\d+(?:\\s*[,\\u2013-]\\s*\\d+)*\\]")
    static let superscripts = Pattern("[\\u00B9\\u00B2\\u00B3\\u2070\\u2074-\\u2079]+")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.bracketed) { _, _ in "" }
        t.replaceMatches(of: Self.superscripts) { _, _ in "" }
        return t
    }
}
