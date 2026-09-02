import Foundation
import T2SLibrary

/// What Readability gives us for a page: the article as a well-formed XHTML fragment (ready for
/// `ArticleEPUBWriter`), the original HTML to retain (spec §2.1), and the plain text for the preview.
public struct ExtractedArticle: Hashable, Sendable {
    public var content: ArticleContent
    public var originalHTML: String
    public var plainText: String

    public var wordCount: Int { plainText.split(whereSeparator: \.isWhitespace).count }

    public init(content: ArticleContent, originalHTML: String, plainText: String) {
        self.content = content
        self.originalHTML = originalHTML
        self.plainText = plainText
    }
}

public enum ExtractionError: Error, Equatable, Sendable {
    case invalidURL
    case network(String)
    /// The page loaded but Readability found no article in it.
    case noArticle
    case timedOut
}

/// The app target implements this with a hidden `WKWebView` + Readability.js; tests use a fake.
public protocol ArticleExtracting: Sendable {
    func extract(from url: URL) async throws -> ExtractedArticle
}
