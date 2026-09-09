import Foundation

/// Rule 4a (spec §4.1). Case-sensitive on purpose: "no." mid-sentence is not "Number".
public struct ExpandAbbreviationsRule: NormalizerRule {
    static let table: [(abbreviation: String, expansion: String)] = [
        ("e.g.", "for example"),
        ("i.e.", "that is"),
        ("No.", "Number"),
        ("Dr.", "Doctor"),
        ("Mr.", "Mister"),
        ("Mrs.", "Missus"),
        ("Ms.", "Miz"),
        ("Prof.", "Professor"),
        ("Jr.", "Junior"),
        ("Sr.", "Senior"),
        ("vs.", "versus"),
        ("etc.", "et cetera"),
        ("Fig.", "Figure"),
        ("approx.", "approximately"),
    ]
    /// "No." only before a number: "Say No. Then leave." keeps its no.
    static let guards: [String: String] = ["No.": "(?=\\s*\\d)"]

    /// One alternation, one pass over the text (Plan 16 — the rule used to run one pass per row).
    /// Every alternative starts at a word boundary and ends with its dot, so at most one of them
    /// can match at any position and the order of the rows does not matter.
    static let pattern = Pattern(
        "\\b(?:" + table.map { NSRegularExpression.escapedPattern(for: $0.abbreviation) + (guards[$0.abbreviation] ?? "") }
            .joined(separator: "|") + ")")
    static let expansions = Dictionary(uniqueKeysWithValues: table.map { ($0.abbreviation, $0.expansion) })

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        // Every abbreviation carries a dot; most utterances carry none but the final one.
        guard input.spoken.utf8.contains(UInt8(ascii: ".")) else { return input }
        var t = input
        t.replaceMatches(of: Self.pattern) { m, s in m.group(0, in: s).flatMap { Self.expansions[$0] } }
        return t
    }
}
