import Foundation
import T2SLibrary
@testable import T2SApp

struct FakeExtractor: ArticleExtracting {
    var article: ExtractedArticle? = ExtractedArticle(
        content: ArticleContent(title: "Fetched Title", byline: "Writer", siteName: "example.com",
                                sourceURL: URL(string: "https://example.com/post"), bodyXHTML: "<p>First paragraph.</p><p>Second one.</p>", excerpt: "First…"),
        originalHTML: "<html><body><p>First paragraph.</p></body></html>",
        plainText: "First paragraph. Second one.")
    var error: ExtractionError?

    func extract(from url: URL) async throws -> ExtractedArticle {
        if let error { throw error }
        guard var article else { throw ExtractionError.noArticle }
        article.content.sourceURL = url
        return article
    }
}
