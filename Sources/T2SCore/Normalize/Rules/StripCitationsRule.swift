/// Rule 3 (spec §4.1): "[14]" must never become "bracket fourteen" — and neither must the footnote
/// number an EPUB leaves glued to the end of a sentence once its superscript markup is flattened:
/// "Daryaganj.14 The presence…", "on me'.18". Those read as "Daryaganj fourteen The presence",
/// and `NLTokenizer` does not even see a sentence boundary there, so the pause goes too. The
/// footnote pattern is one to three digits straight after sentence-final punctuation (closing
/// quotes or brackets allowed between), followed by a capital or the end; a digit before the
/// punctuation ("3.14 dollars", "v2.0 The") or a lowercase word after ("p.14 for", "Fig.3 shows")
/// keeps it, since those are decimals, versions and references (owner's ask, 2026-09-09).
public struct StripCitationsRule: NormalizerRule {
    static let bracketed = Pattern(" ?\\[\\d+(?:\\s*[,\\u2013-]\\s*\\d+)*\\]")
    static let superscripts = Pattern("[\\u00B9\\u00B2\\u00B3\\u2070\\u2074-\\u2079]+")
    static let footnotes = Pattern("(?<=[^\\d\\s][.!?\\u2026]['\"\\u2019\\u201D)\\]]{0,3})\\d{1,3}(?=\\s+['\"\\u201C\\u2018(]?\\p{Lu}|\\s*$)")

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.bracketed) { _, _ in "" }
        t.replaceMatches(of: Self.superscripts) { _, _ in "" }
        t.replaceMatches(of: Self.footnotes) { _, _ in "" }
        return t
    }
}
