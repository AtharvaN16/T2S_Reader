import T2SCore

/// SwiftData persistence for documents, chapter blobs, positions, bookmarks, and the dictionary (spec §5).
public enum T2SStore {
    /// The T2SCore schema this build of T2SStore was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
