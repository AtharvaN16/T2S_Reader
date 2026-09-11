/// The import rows of spec §6.
public enum ImportError: Error, Equatable, Sendable {
    /// Rejected at import with a plain explanation; never silently (spec §6).
    case drmProtected
    case unsupportedFormat(String)
    case unreadable(String)
    /// The source parsed but produced no speakable text (a scanned PDF, an empty extraction).
    case noText
    /// The article body is not well-formed XHTML.
    case malformedBody(String)
    /// The file offered for a placeholder is not the file the other device has (sync spec §5).
    case differentFile
    /// A document with this content key — the same bytes, or the same article URL — is already in
    /// the library. One row per key (sync spec §2): a second one would sync as the same record and
    /// the two would overwrite each other forever.
    case alreadyInLibrary
}
