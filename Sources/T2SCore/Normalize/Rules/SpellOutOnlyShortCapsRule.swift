import Foundation

/// A word set in capitals is a word, not a spelling. The phonemiser treats any all-caps token it
/// cannot find in its dictionary as a proper noun and reads it letter by letter, so a title page or
/// a heading — "SUPERFORECASTING", "THE ART AND SCIENCE OF PREDICTION" — came out as an alphabet
/// (owner, 2026-09-12). Lowercasing a long run of capitals hands the phonemiser an ordinary word
/// and it says it.
///
/// Short runs are left alone, because those are the ones that really are spelled: "FBI", "USA",
/// "PDF". Five letters is the line — long enough to clear almost every initialism, short enough to
/// catch a word in a heading.
///
/// The change is case only, so every offset is where it was: the spoken string keeps the source's
/// length, and the highlight and the bookmarks map through it unmoved.
public struct SpellOutOnlyShortCapsRule: NormalizerRule {
    /// Runs of five or more capitals, apostrophes allowed inside ("READER'S").
    static let shouted = Pattern("\\p{Lu}[\\p{Lu}'\\u2019]{4,}")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var text = input
        text.replaceMatches(of: Self.shouted) { match, spoken in
            let ns: NSString = spoken as NSString
            return ns.substring(with: match.range).lowercased()
        }
        return text
    }
}
