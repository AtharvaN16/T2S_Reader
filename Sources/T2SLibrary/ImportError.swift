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
}
