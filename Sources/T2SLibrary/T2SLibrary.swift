import T2SCore

/// Ingest and library orchestration: readers, the article-to-EPUB writer, the app-container layout,
/// and the `Library` facade over `T2SStore` (spec §4).
public enum T2SLibrary {
    /// The T2SCore schema this build of T2SLibrary was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
