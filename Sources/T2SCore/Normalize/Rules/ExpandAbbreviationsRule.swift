/// Rule 4a (spec §4.1). Case-sensitive on purpose: "no." mid-sentence is not "Number".
public struct ExpandAbbreviationsRule: NormalizerRule {
    static let table: [(Pattern, String)] = [
        (Pattern("\\be\\.g\\."), "for example"),
        (Pattern("\\bi\\.e\\."), "that is"),
        (Pattern("\\bNo\\.(?=\\s*\\d)"), "Number"),
        (Pattern("\\bDr\\."), "Doctor"),
        (Pattern("\\bMr\\."), "Mister"),
        (Pattern("\\bMrs\\."), "Missus"),
        (Pattern("\\bMs\\."), "Miz"),
        (Pattern("\\bProf\\."), "Professor"),
        (Pattern("\\bJr\\."), "Junior"),
        (Pattern("\\bSr\\."), "Senior"),
        (Pattern("\\bvs\\."), "versus"),
        (Pattern("\\betc\\."), "et cetera"),
        (Pattern("\\bFig\\."), "Figure"),
        (Pattern("\\bapprox\\."), "approximately"),
    ]

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        for (pattern, replacement) in Self.table {
            t.replaceMatches(of: pattern) { _, _ in replacement }
        }
        return t
    }
}
