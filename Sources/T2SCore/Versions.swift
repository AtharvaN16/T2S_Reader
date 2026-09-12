/// Bump a version whenever the output of that stage changes shape or content.
/// Persisted timelines record all three; a mismatch forces re-derivation (spec §3.7.4).
public enum Versions {
    public static let schema = 1
    /// 2 (2026-09-06): consecutive sentences of a block pack into one utterance (`Segmenter.packLength`).
    public static let segmenter = 2
    /// 4 (2026-09-09): a footnote number glued to sentence-final punctuation is dropped
    /// (`StripCitationsRule.footnotes`) — every chapter of a footnoted book said them aloud, so this
    /// one is worth the re-derivation it costs.
    /// 3 (2026-09-08): a hyphen joining two words becomes a space (`SplitHyphenatedCompoundsRule`).
    /// Not bumped for Plan 16's one-pass dictionary (2026-09-08): its output differs only for a
    /// dictionary whose entries chain (one replacement contains another's term) or overlap, which a
    /// reader would have to build on purpose; a bump would re-derive and re-render every book.
    /// 5 (2026-09-12): a run of five or more capitals is lowercased, so the phonemiser says the
    /// word instead of spelling it (`SpellOutOnlyShortCapsRule`). Worth the re-derivation: a book
    /// whose title page or headings are set in capitals read them out as an alphabet.
    public static let normalizer = 5
}
