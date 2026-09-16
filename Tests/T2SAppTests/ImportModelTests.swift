import Foundation
import Testing
import T2SCore
import T2SLibrary
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct ImportModelTests {
    @Test func linkFlowFetchesPreviewsAndImports() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        let url = URL(string: "https://example.com/post")!
        await model.fetch(link: url)
        guard case .preview(let article) = model.phase else { Issue.record("expected preview, got \(model.phase)"); return }
        #expect(article.wordCount == 4)                                      // "First paragraph. Second one." (brief's ImportModelTests said 5; actual is 4)
        #expect(model.isThinPreview)                                         // 4 words < 120
        await model.confirmPreview()
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(docs.count == 1)
        #expect(docs[0].document.sourceType == .article && docs[0].document.sourceURL == url)
        #expect(docs[0].document.title == "Fake Book")                      // the reader's title wins (spec §2.1: one reflowable path)
        #expect(try await f.store.queue().map(\.id) == [docs[0].id])
        #expect(FileManager.default.fileExists(atPath: f.paths.originalHTMLURL(docs[0].id).path))
        model.reset()
        #expect(model.phase == .idle)
    }

    @Test func extractionFailureIsInline() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor(error: .network("offline")))
        await model.fetch(link: URL(string: "https://example.com/x")!)
        #expect(model.phase == .failed("Couldn't load the page: offline"))
        await model.fetch(link: URL(string: "notaurl")!)
        #expect(model.phase == .failed("That doesn't look like a web address."))
    }

    @Test func importFailureAfterPreviewIsInline() async throws {
        let f = try AppFixtures(readers: [])                                  // no reader for articles
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        await model.fetch(link: URL(string: "https://example.com/post")!)
        await model.confirmPreview()
        #expect(model.phase == .failed("This kind of file isn't supported (article)."))
    }

    /// A link straight to a book downloads and imports it, with no preview to confirm: there is no
    /// article to look at. This is the way past Apple Books, which swallows an EPUB downloaded on
    /// the phone before it ever reaches Files (owner, 2026-09-16).
    @Test func aBookLinkDownloadsAndImportsWithoutAPreview() async throws {
        let f = try AppFixtures()
        let downloader = FakeBookDownloader(name: "frankenstein.epub")
        let model = ImportModel(library: f.library, extractor: FakeExtractor(error: .noArticle), downloader: downloader)
        await model.fetch(link: URL(string: "https://example.com/books/frankenstein.epub")!)
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(docs.count == 1)
        #expect(docs[0].document.sourceType == .epub)
        #expect(model.fileRows.map(\.name) == ["frankenstein.epub"])         // the book's name, not a UUID
        let file = try #require(downloader.delivered.url)
        #expect(!FileManager.default.fileExists(atPath: file.path))          // the scratch copy goes with the import
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }

    @Test func aBookLinkThatFailsSaysWhyInline() async throws {
        let f = try AppFixtures()
        let link = URL(string: "https://example.com/books/frankenstein.epub")!

        let missing = ImportModel(library: f.library, extractor: FakeExtractor(),
                                  downloader: FakeBookDownloader(error: .server(404)))
        await missing.fetch(link: link)
        #expect(missing.phase == .failed("That link didn't work (404)."))

        let wall = ImportModel(library: f.library, extractor: FakeExtractor(),
                               downloader: FakeBookDownloader(error: .notABook("text/html")))
        await wall.fetch(link: link)
        #expect(wall.phase == .failed("That link isn't an EPUB or a PDF (text/html)."))

        let offline = ImportModel(library: f.library, extractor: FakeExtractor(),
                                  downloader: FakeBookDownloader(error: .network("offline")))
        await offline.fetch(link: link)
        #expect(offline.phase == .failed("Couldn't download that file: offline"))
    }

    /// What came back decides what it is: the content type first, the server's filename next, the
    /// address last — and an HTML page behind a `.epub` address is not a book at all.
    @Test func whatCameBackDecidesTheKind() {
        let epubLink = URL(string: "https://example.com/books/frankenstein.epub")!
        let plainLink = URL(string: "https://example.com/download?id=42")!
        typealias D = URLSessionBookDownloader
        #expect(D.bookExtension(mimeType: "application/epub+zip", url: plainLink, suggestedFilename: nil) == "epub")
        #expect(D.bookExtension(mimeType: "application/pdf; charset=binary", url: plainLink, suggestedFilename: nil) == "pdf")
        #expect(D.bookExtension(mimeType: "application/octet-stream", url: plainLink, suggestedFilename: "Frankenstein.EPUB") == "epub")
        #expect(D.bookExtension(mimeType: "application/octet-stream", url: epubLink, suggestedFilename: nil) == "epub")
        #expect(D.bookExtension(mimeType: "text/html", url: epubLink, suggestedFilename: "login.html") == nil)
        #expect(D.bookExtension(mimeType: nil, url: plainLink, suggestedFilename: nil) == nil)
        #expect(D.filename(from: "Frankenstein.EPUB", kind: "epub") == "Frankenstein.epub")
        #expect(D.filename(from: "", kind: "pdf") == "book.pdf")
    }

    @Test func pastedTextImports() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        await model.importText(title: "", body: "A pasted note.\n\nWith two paragraphs.")
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(docs[0].document.sourceType == .article && docs[0].document.sourceURL == nil)
        await model.importText(title: "", body: "   ")
        #expect(model.phase == .failed("There's no text to read."))
    }

    /// One `ImportModel` serves the Add sheet and files opened from other apps; a second request
    /// while one is in flight must be refused rather than overwrite the live state machine.
    @Test func aSecondRequestIsRefusedWhileOneIsInFlight() async throws {
        let f = try AppFixtures()
        let gate = ExtractorGate()
        let model = ImportModel(library: f.library, extractor: FakeExtractor(gate: gate))
        let url = URL(string: "https://example.com/post")!
        let fetching = Task { await model.fetch(link: url) }
        while !model.isBusy { await Task.yield() }                            // parked on the gate
        await model.importText(title: "", body: "A pasted note.")
        #expect(model.phase == .fetching(url))                                // untouched
        await model.importFiles([URL(fileURLWithPath: "/tmp/none.epub")])
        #expect(model.phase == .fetching(url) && model.fileRows.isEmpty)
        await gate.open()
        await fetching.value
        guard case .preview = model.phase else { Issue.record("expected preview, got \(model.phase)"); return }
    }

    @Test func filesImportOneByOneWithRows() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        let good = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).epub")
        try Data("PK".utf8).write(to: good)
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: bad)
        await model.importFiles([good, bad])
        #expect(model.fileRows.map(\.name) == [good.lastPathComponent, bad.lastPathComponent])
        guard case .done(let docs) = model.fileRows[0].state else { Issue.record("expected done"); return }
        #expect(docs.document.sourceType == .epub)
        #expect(model.fileRows[1].state == .failed("This kind of file isn't supported (txt)."))
        guard case .done(let imported) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(imported.map(\.id) == [docs.id])
        await model.importFiles([bad])
        #expect(model.phase == .failed("Nothing could be imported."))
    }

    /// Whoever wires the model — the app — primes the new documents so their first tap plays at once;
    /// the hook carries the summaries so it need not look them up again.
    @Test func afterImportReceivesEveryImportedDocument() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        var received: [[UUID]] = []
        model.afterImport = { docs in received.append(docs.map(\.id)) }

        await model.importText(title: "", body: "A pasted note.")
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(received == [[docs[0].id]])

        await model.importText(title: "", body: "   ")                       // fails before importing
        #expect(received.count == 1)
    }
}
