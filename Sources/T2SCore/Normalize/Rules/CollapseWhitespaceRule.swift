/// Runs after every content rule and before the pronunciation dictionary.
public struct CollapseWhitespaceRule: NormalizerRule {
    static let runs = Pattern("\\s+")
    static let edges = Pattern("^\\s+|\\s+$")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.edges) { _, _ in "" }
        t.replaceMatches(of: Self.runs) { m, s in
            m.group(0, in: s) == " " ? nil : " "
        }
        return t
    }
}
