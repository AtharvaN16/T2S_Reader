import Foundation
import T2SLibrary
@testable import T2SApp

/// Parks `extract` until `open()` — lets a test observe a fetch that is genuinely in flight
/// without a sleep.
actor ExtractorGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters.removeAll()
        waiting.forEach { $0.resume() }
    }
}

struct FakeExtractor: ArticleExtracting {
    var article: ExtractedArticle? = ExtractedArticle(
        content: ArticleContent(title: "Fetched Title", byline: "Writer", siteName: "example.com",
                                sourceURL: URL(string: "https://example.com/post"), bodyXHTML: "<p>First paragraph.</p><p>Second one.</p>", excerpt: "First…"),
        originalHTML: "<html><body><p>First paragraph.</p></body></html>",
        plainText: "First paragraph. Second one.")
    var error: ExtractionError?
    var gate: ExtractorGate?

    func extract(from url: URL) async throws -> ExtractedArticle {
        await gate?.wait()
        if let error { throw error }
        guard var article else { throw ExtractionError.noArticle }
        article.content.sourceURL = url
        return article
    }
}
