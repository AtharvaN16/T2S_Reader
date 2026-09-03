// App/T2SReader/Import/ArticleExtractor.swift
import Foundation
import T2SApp
import T2SLibrary
import WebKit

/// Loads the page in a hidden `WKWebView`, runs Readability.js, and serializes the article to an
/// XHTML fragment with `XMLSerializer` (images, media, and scripts removed: this is a listening app).
/// The Share Extension (Plan 5) reuses this class.
@MainActor
final class ArticleExtractor: NSObject, ArticleExtracting, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ExtractedArticle, any Error>?
    private var timeout: Task<Void, Never>?
    private var url: URL?

    static let timeoutSeconds: UInt64 = 20

    /// One main-actor hop: the continuation is recorded *before* the load starts, so a navigation
    /// callback that lands immediately still finds it rather than ending the request by timeout.
    nonisolated func extract(from url: URL) async throws -> ExtractedArticle {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    guard self.continuation == nil, self.webView == nil else { throw ExtractionError.network("an extraction is already running") }
                    self.continuation = continuation
                    try self.begin(url)
                } catch {
                    self.continuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func begin(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw ExtractionError.invalidURL }
        self.url = url
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            self?.fail(ExtractionError.timedOut)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await runReadability() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        fail(ExtractionError.network(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        fail(ExtractionError.network(error.localizedDescription))
    }

    private func runReadability() async {
        guard let webView, let url else { return }
        guard let scriptURL = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let library = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            fail(ExtractionError.network("Readability.js is missing from the app bundle"))
            return
        }
        let runner = library + """

        (function () {
          var original = document.documentElement.outerHTML;
          var article = new Readability(document.cloneNode(true)).parse();
          if (!article || !article.content) { return null; }
          var container = document.createElementNS('http://www.w3.org/1999/xhtml', 'div');
          container.innerHTML = article.content;
          container.querySelectorAll('img, picture, figure, video, audio, iframe, svg, script, style, noscript, form, button').forEach(function (n) { n.remove(); });
          var xhtml = new XMLSerializer().serializeToString(container).replace(/&nbsp;/g, '\\u00a0');
          return { title: article.title || document.title || '', byline: article.byline || null, siteName: article.siteName || null,
                   excerpt: article.excerpt || null, lang: article.lang || document.documentElement.lang || null,
                   text: article.textContent || '', content: xhtml, html: original };
        })();
        """
        do {
            let result = try await webView.evaluateJavaScript(runner)
            guard let dict = result as? [String: Any], let content = dict["content"] as? String, !content.isEmpty else {
                fail(ExtractionError.noArticle)
                return
            }
            let title = (dict["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? "Article"
            let article = ExtractedArticle(
                content: ArticleContent(title: title, byline: dict["byline"] as? String, siteName: dict["siteName"] as? String,
                                        sourceURL: url, language: (dict["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "en",
                                        bodyXHTML: content, excerpt: dict["excerpt"] as? String),
                originalHTML: dict["html"] as? String ?? "",
                plainText: dict["text"] as? String ?? "")
            succeed(article)
        } catch {
            fail(ExtractionError.network("Readability failed: \(error.localizedDescription)"))
        }
    }

    private func succeed(_ article: ExtractedArticle) {
        guard let continuation else { return }
        teardown()
        continuation.resume(returning: article)
    }

    private func fail(_ error: ExtractionError) {
        guard let continuation else { return }
        teardown()
        continuation.resume(throwing: error)
    }

    private func teardown() {
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        continuation = nil
        url = nil
    }
}
