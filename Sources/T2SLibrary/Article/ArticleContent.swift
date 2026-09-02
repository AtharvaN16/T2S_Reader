import Foundation

/// A web article after Readability extraction (spec §2.1), ready to be written as a minimal EPUB.
public struct ArticleContent: Hashable, Sendable {
    public var title: String
    public var byline: String?
    public var siteName: String?
    public var sourceURL: URL?
    /// BCP-47 tag for `xml:lang`. Readability rarely knows it; v1 is English-only (spec §7.1).
    public var language: String
    /// The article body as a **well-formed XHTML fragment**. The Share Extension serializes
    /// Readability's output with `XMLSerializer`, which produces exactly this; the writer validates
    /// and rejects anything else (`ImportError.malformedBody`).
    public var bodyXHTML: String
    public var excerpt: String?

    public init(title: String, byline: String? = nil, siteName: String? = nil, sourceURL: URL? = nil,
                language: String = "en", bodyXHTML: String, excerpt: String? = nil) {
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.sourceURL = sourceURL
        self.language = language
        self.bodyXHTML = bodyXHTML
        self.excerpt = excerpt
    }
}
