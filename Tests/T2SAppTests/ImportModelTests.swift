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
}
