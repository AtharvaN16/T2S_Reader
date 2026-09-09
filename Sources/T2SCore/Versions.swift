/// Bump a version whenever the output of that stage changes shape or content.
/// Persisted timelines record all three; a mismatch forces re-derivation (spec §3.7.4).
public enum Versions {
    public static let schema = 1
    /// 2 (2026-09-06): consecutive sentences of a block pack into one utterance (`Segmenter.packLength`).
    public static let segmenter = 2
    /// 3 (2026-09-08): a hyphen joining two words becomes a space (`SplitHyphenatedCompoundsRule`).
    /// Not bumped for Plan 16's one-pass dictionary (2026-09-08): its output differs only for a
    /// dictionary whose entries chain (one replacement contains another's term) or overlap, which a
    /// reader would have to build on purpose; a bump would re-derive and re-render every book.
    public static let normalizer = 3
}
