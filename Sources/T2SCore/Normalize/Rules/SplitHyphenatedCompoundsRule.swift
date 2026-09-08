import Foundation

/// Rule 4b (spec §4.1): a hyphen joining two words is spoken as a word break, not as a dash —
/// "commander-in-chief" → "commander in chief", "cost-cutting" → "cost cutting", "COVID-19" → "COVID 19".
///
/// Why the app resolves this rather than the G2P: MisakiSwift tokenizes with `NLTagger`, which makes
/// every hyphen a token of its own tagged `.dash`, and turns every `.dash` token into Kokoro's `—` — the
/// em dash, which the duration model gives a clause-length pause and which leaves the next word stressed
/// as a word of its own, so "cost-cutting" was read "cost — CUTTING" with a 150 ms hole in it. The Python
/// reference tells an intra-word hyphen (spaCy `HYPH`, silent) from a dash that stands alone (`:`, a
/// pause); MisakiSwift cannot, so the hyphen has to be resolved before the text reaches it. A dash with
/// space around it, a double hyphen, an em or an en dash are left alone: those are real pauses. So is a
/// hyphen between two digits ("1990-1995", "555-1234"): a range or a phone number reads better with the
/// beat. `RejoinHyphenationRule` runs first, so a word broken across a line is whole again before this
/// rule looks at it. Finding: `spikes/findings/2026-09-08-ticks-and-hyphens.md`.
public struct SplitHyphenatedCompoundsRule: NormalizerRule {
    /// A hyphen-minus, a Unicode hyphen (U+2010) or a non-breaking hyphen (U+2011) with a letter or a
    /// digit on each side, at least one of them a letter.
    static let pattern = Pattern("(?<=\\p{L})[-\\u2010\\u2011](?=[\\p{L}\\p{N}])|(?<=\\p{N})[-\\u2010\\u2011](?=\\p{L})")

    public init() {}

    /// `text` as this rule would speak it. The pronunciation dictionary runs after this rule, so a term
    /// the reader typed with a hyphen is matched in this form.
    static func spokenForm(of text: String) -> String {
        pattern.regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
    }

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.pattern) { _, _ in " " }
        return t
    }
}
