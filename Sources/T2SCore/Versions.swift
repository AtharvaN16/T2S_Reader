/// Bump a version whenever the output of that stage changes shape or content.
/// Persisted timelines record all three; a mismatch forces re-derivation (spec §3.7.4).
public enum Versions {
    public static let schema = 1
    /// 2 (2026-09-06): consecutive sentences of a block pack into one utterance (`Segmenter.packLength`).
    public static let segmenter = 2
    /// 3 (2026-09-08): a hyphen joining two words becomes a space (`SplitHyphenatedCompoundsRule`).
    public static let normalizer = 3
}
