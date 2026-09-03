/// Bump a version whenever the output of that stage changes shape or content.
/// Persisted timelines record all three; a mismatch forces re-derivation (spec §3.7.4).
public enum Versions {
    public static let schema = 1
    public static let segmenter = 1
    public static let normalizer = 2
}
