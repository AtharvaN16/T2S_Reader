/// Rule 5 (spec §4.1): a URL is spoken as its bare host.
public struct CollapseURLsRule: NormalizerRule {
    static let pattern = Pattern("\\b(?:https?://)?(?:www\\.)?([A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+)(?:/\\S*)?\\s?", [])
    static let schemeOrWWW = Pattern("^(?:https?://|www\\.)")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.pattern) { m, s in
            guard let whole = m.group(0, in: s), let host = m.group(1, in: s) else { return nil }
            // Only touch things that look like URLs: a scheme, a www., or a path.
            let looksLikeURL = whole.hasPrefix("http") || whole.hasPrefix("www.") || whole.contains("/")
            if looksLikeURL {
                // Preserve trailing space if the match included one
                return whole.hasSuffix(" ") ? host + " " : host
            }
            return nil
        }
        return t
    }
}
