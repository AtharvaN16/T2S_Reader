import Foundation
import Testing
import T2SCore
@testable import T2SStore
@testable import T2SLibrary

@Suite struct LibraryTests {
    struct Harness {
        let library: Library
        let paths: LibraryPaths
        let store: LibraryStore
        let audio: InMemoryAudioStore
    }

    /// One sentence per utterance unless a test asks for the app's packing: these tests count
    /// sentences; packing is the segmenter's own test, plus `packsSentencesAtTheAppsLength` below.
    func makeHarness(readers: [any DocumentReader], packLength: Int = 0) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-lib-\(UUID().uuidString)")
        let paths = LibraryPaths(root: root)
        let store = try LibraryStore.inMemory()
        let audio = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let library = Library(paths: paths, store: store, audioStore: audio, readers: readers, segmenterPackLength: packLength)
        return Harness(library: library, paths: paths, store: store, audio: audio)
    }

    /// The production `Library` packs (Plan 9 Task 2): the two sentences of page one become one
    /// utterance, page two stays its own (packing never crosses a block).
    @Test func packsSentencesAtTheAppsLength() async throws {
        let h = try makeHarness(readers: [PDFDocumentReader()], packLength: Segmenter.appPackLength)
        let pdf = try PDFFixture.write(pages: [["Hello from page one.", "And a second line."], ["Page two speaks."]],
                                       title: "Two Pages")
        let result = try await h.library.importFile(at: pdf, sourceType: .pdf)
        #expect(result.utteranceCount == 2)
        let timeline = try #require(try await h.store.timeline(for: result.document.id)?.timeline)
        // The page's lines are joined by a newline; the packed source keeps the text between sentences.
        #expect(timeline[utterance: 0].source == "Hello from page one.\nAnd a second line.")
        #expect(timeline[utterance: 1].source == "Page two speaks.")
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func scratchFile(_ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).\(ext)")
        try Data("PK".utf8).write(to: url)
        return url
    }

    private func importFake(_ h: Harness) async throws -> ImportResult {
        try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
    }

    @Test func importsAPDF() async throws {
        let h = try makeHarness(readers: [PDFDocumentReader()])
        let pdf = try PDFFixture.write(pages: [["Hello from page one.", "And a second line."], ["Page two speaks."]],
                                       title: "Two Pages")
        let result = try await h.library.importFile(at: pdf, sourceType: .pdf)
        let doc = result.document
        #expect(doc.title == "Two Pages" && doc.sourceType == .pdf && doc.sourceURL == nil)
        #expect(result.utteranceCount == 3 && result.skippedResources.isEmpty)
        #expect(exists(h.paths.sourceURL(doc.id, type: .pdf)))
        #expect(exists(pdf))                                                // copied, never moved
        #expect(doc.coverImagePath == h.paths.relativePath(of: h.paths.coverURL(doc.id)))
        #expect(exists(h.paths.coverURL(doc.id)))
        #expect(try await h.store.queue().map(\.id) == [doc.id])
        #expect(try await h.store.timeline(for: doc.id)?.timeline.utteranceCount == 3)
        #expect(try await h.library.timelineForPlayback(doc.id)?.chapters.first?.title == "Two Pages")
    }

    @Test func importsAnEPUBThroughTheReader() async throws {
        let reader = FakeDocumentReader()
        let h = try makeHarness(readers: [PDFDocumentReader(), reader])
        let result = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        let doc = result.document
        #expect(await reader.log.urls == [h.paths.sourceURL(doc.id, type: .epub)])
        #expect(doc.title == "Fake Book" && doc.author == "Fake Author" && doc.sourceType == .epub)
        let timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        #expect(timeline.chapters.map(\.title) == ["One", "Two"])
        #expect(timeline.utteranceCount == 3)
        #expect(try await h.store.queue().map(\.id) == [doc.id])
        #expect(try await h.store.collection().map(\.id) == [doc.id])
    }

    @Test func importsAnArticleAsAnEPUBAndKeepsTheHTML() async throws {
        let reader = FakeDocumentReader(skipped: ["OEBPS/blank.xhtml"])
        let h = try makeHarness(readers: [reader])
        let article = ArticleContent(title: "An Article", byline: "Jane", sourceURL: URL(string: "https://example.com/a"),
                                     bodyXHTML: "<p>Body text.</p>")
        let result = try await h.library.importArticle(article, originalHTML: "<html><body><p>Body text.</p></body></html>")
        let doc = result.document
        #expect(doc.sourceType == .article && doc.sourceURL == article.sourceURL)
        #expect(result.skippedResources == ["OEBPS/blank.xhtml"])
        #expect(try String(contentsOf: h.paths.originalHTMLURL(doc.id), encoding: .utf8).contains("<p>Body text.</p>"))
        let epub = try Data(contentsOf: h.paths.sourceURL(doc.id, type: .article))
        #expect(epub.prefix(2) == Data("PK".utf8))
        #expect(await reader.log.urls == [h.paths.sourceURL(doc.id, type: .article)])
        #expect(try await h.store.queue().map(\.id) == [doc.id])
        #expect(try await h.store.collection().isEmpty)
    }

    @Test func malformedArticleLeavesNothingBehind() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let article = ArticleContent(title: "Bad", bodyXHTML: "<p>unclosed")
        await #expect(throws: ImportError.self) { _ = try await h.library.importArticle(article, originalHTML: "<p>") }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: h.paths.documentsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func unsupportedTypeLeavesNothingBehind() async throws {
        let h = try makeHarness(readers: [PDFDocumentReader()])
        await #expect(throws: ImportError.unsupportedFormat("epub")) {
            _ = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        }
        #expect(!exists(h.paths.documentsDirectory))
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func readerFailureCleansUp() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader(failure: .drmProtected)])
        await #expect(throws: ImportError.drmProtected) {
            _ = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: h.paths.documentsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func noTextIsRejected() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader(chapters: [])])
        await #expect(throws: ImportError.noText) {
            _ = try await h.library.importFile(at: try scratchFile("epub"), sourceType: .epub)
        }
        #expect(try await h.store.documents().isEmpty)
    }

    @Test func deleteRemovesRowsFilesAndAudio() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        let key = RenderKey(rawValue: "k1")
        try await h.audio.write(PCMAudio(samples: [0, 0, 0]), for: key)
        var timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        timeline[utterance: 0].audioRef = key.rawValue
        try await h.store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)

        try await h.library.delete(doc.id)
        #expect(try await h.store.document(id: doc.id) == nil)
        #expect(!exists(h.paths.documentDirectory(doc.id)))
        #expect(await h.audio.contains(key) == false)
    }

    @Test func staleTimelineIsReprocessedForPlayback() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        let resume = Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0)
        try await h.store.savePosition(resume, for: doc.id)
        // A timeline persisted by an older segmenter, with one rendered utterance under the old key.
        let oldKey = RenderKey(rawValue: "old")
        try await h.audio.write(PCMAudio(samples: [0]), for: oldKey)
        var stale = try #require(try await h.store.timeline(for: doc.id)).timeline
        stale.segmenterVersion = Versions.segmenter + 1
        stale[utterance: 0].audioRef = oldKey.rawValue
        try await h.store.replaceTimeline(stale, for: doc.id)
        #expect(try await h.store.timeline(for: doc.id)?.isStale == true)

        let fresh = try #require(try await h.library.timelineForPlayback(doc.id))
        #expect(fresh.segmenterVersion == Versions.segmenter && fresh.utteranceCount == 3)
        #expect(fresh.chapters.allSatisfy { $0.utterances.allSatisfy { $0.audioRef == nil } })
        #expect(try await h.store.timeline(for: doc.id)?.isStale == false)
        await h.library.awaitAudioGC()
        #expect(await h.audio.contains(oldKey) == false)                    // orphan removed, behind the load
        #expect(try await h.store.document(id: doc.id)?.resumePosition == resume)
        #expect(PositionResolver.resolve(resume, in: fresh).utteranceIndex == 2)
    }

    @Test func evictAudioClearsRefsAndKeepsDurations() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        let key = RenderKey(rawValue: "k2")
        try await h.audio.write(PCMAudio(samples: [0, 0]), for: key)
        var timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        timeline[utterance: 1].audioRef = key.rawValue
        timeline[utterance: 1].duration = .actual(0.75)
        try await h.store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)

        try await h.library.evictAudio(for: doc.id)
        let after = try #require(try await h.store.timeline(for: doc.id)).timeline
        #expect(after[utterance: 1].audioRef == nil)
        #expect(after[utterance: 1].duration == .actual(0.75))
        #expect(await h.audio.contains(key) == false)
        #expect(try await h.store.summary(id: doc.id)?.renderedCount == 0)
    }

    @Test func renderSnapshotFollowsResumeAndAudioRefs() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        try await h.store.savePosition(Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), for: doc.id)
        var timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        timeline[utterance: 0].audioRef = "k3"
        try await h.store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)
        let snapshot = try #require(try await h.library.renderSnapshot(for: doc.id))
        #expect(snapshot.documentID == doc.id)
        #expect(snapshot.rendered == [true, false, false])
        #expect(snapshot.resumeIndex == 2)
        #expect(snapshot.seconds.count == 3)
        #expect(try await h.library.renderSnapshot(for: UUID()) == nil)
    }

    @Test func dictionaryIsAppliedAtImportAndOnReprocess() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        try await h.store.upsert(PronunciationEntry(term: "Second", replacement: "2nd"))
        let doc = try await importFake(h).document
        let timeline = try #require(try await h.store.timeline(for: doc.id)).timeline
        #expect(timeline[utterance: 1].spoken == "2nd sentence.")
        #expect(timeline[utterance: 1].source == "Second sentence.")
        try await h.store.upsert(PronunciationEntry(term: "Third", replacement: "3rd"))
        // The versions do not move, so the new render keys are the old ones: the old audio must be
        // gone before the replacement, or the next render would play the old pronunciation.
        let oldKey = RenderKey(rawValue: "old")
        try await h.audio.write(PCMAudio(samples: [0]), for: oldKey)
        var rendered = timeline
        rendered[utterance: 2].audioRef = oldKey.rawValue
        try await h.store.replaceTimeline(rendered, for: doc.id)
        let reprocessed = try await h.library.reprocess(doc.id)
        #expect(reprocessed[utterance: 2].spoken == "3rd sentence.")
        #expect(try await h.store.timeline(for: doc.id)?.timeline == reprocessed)
        #expect(await h.audio.contains(oldKey) == false)                    // removed on the way, not behind it
    }

    /// A retained file that cannot be read — a bad frame, a shape change — falls back to the reader
    /// and is written again.
    @Test func aCorruptRetainedFileFallsBackToTheReaderAndIsRewritten() async throws {
        let reader = FakeDocumentReader()
        let h = try makeHarness(readers: [reader])
        let doc = try await importFake(h).document
        try Data("not lzfse".utf8).write(to: h.paths.retainedChaptersURL(doc.id))
        let reprocessed = try await h.library.reprocess(doc.id)
        #expect(reprocessed.utteranceCount == 3)
        #expect(await reader.log.urls.count == 2)
        #expect(try RetainedChapters.read(from: h.paths.retainedChaptersURL(doc.id))?.count == 2)
    }

    /// Import keeps the reader's chapters beside the source, and a re-derivation starts from them
    /// (Plan 17, audit §5.1): the source is not opened again — here it is not even there.
    @Test func reprocessReadsTheRetainedChaptersNotTheSource() async throws {
        let reader = FakeDocumentReader()
        let h = try makeHarness(readers: [reader])
        let doc = try await importFake(h).document
        #expect(FileManager.default.fileExists(atPath: h.paths.retainedChaptersURL(doc.id).path))
        try FileManager.default.removeItem(at: h.paths.sourceURL(doc.id, type: .epub))
        var stale = try #require(try await h.store.timeline(for: doc.id)).timeline
        stale.segmenterVersion = Versions.segmenter + 1
        try await h.store.replaceTimeline(stale, for: doc.id)

        let fresh = try #require(try await h.library.timelineForPlayback(doc.id))
        #expect(fresh.utteranceCount == 3 && fresh.segmenterVersion == Versions.segmenter)
        #expect(await reader.log.urls.count == 1)                          // the import's read, and no other
    }

    /// A document imported before chapters were retained reads its source once more, and keeps the
    /// result for the next time.
    @Test func aDocumentWithoutRetainedChaptersReadsTheSourceOnceAndRetainsIt() async throws {
        let reader = FakeDocumentReader()
        let h = try makeHarness(readers: [reader])
        let doc = try await importFake(h).document
        try FileManager.default.removeItem(at: h.paths.retainedChaptersURL(doc.id))
        _ = try await h.library.reprocess(doc.id)
        #expect(await reader.log.urls.count == 2)
        #expect(FileManager.default.fileExists(atPath: h.paths.retainedChaptersURL(doc.id).path))
        _ = try await h.library.reprocess(doc.id)
        #expect(await reader.log.urls.count == 2)                          // retained now
    }

    /// The render snapshot is for Prepare, which must never re-derive a book on its own (audit §5.1):
    /// a stale document has no snapshot until it is opened.
    @Test func renderSnapshotNeverReDerives() async throws {
        let reader = FakeDocumentReader()
        let h = try makeHarness(readers: [reader])
        let doc = try await importFake(h).document
        var stale = try #require(try await h.store.timeline(for: doc.id)).timeline
        stale.normalizerVersion = Versions.normalizer + 1
        try await h.store.replaceTimeline(stale, for: doc.id)
        #expect(try await h.library.renderSnapshot(for: doc.id) == nil)
        #expect(try await h.store.isStale(id: doc.id) == true)
        _ = try await h.library.timelineForPlayback(doc.id)
        #expect(try await h.library.renderSnapshot(for: doc.id)?.rendered.count == 3)
    }

    /// An undecodable chapter blob must never make a document unplayable *and* undeletable: the
    /// staleness check reads only the row's version columns, and both `reprocess` and `delete`
    /// tolerate a `timeline(for:)` that throws.
    @Test func corruptBlobStillDeletesAndReprocesses() async throws {
        let h = try makeHarness(readers: [FakeDocumentReader()])
        let doc = try await importFake(h).document
        try await h.store.corruptChapterBlob(0, of: doc.id)
        await #expect(throws: (any Error).self) { _ = try await h.store.timeline(for: doc.id) }

        let reprocessed = try await h.library.reprocess(doc.id)
        #expect(reprocessed.utteranceCount == 3)
        #expect(try await h.store.timeline(for: doc.id)?.timeline == reprocessed)

        let other = try await importFake(h).document
        try await h.store.corruptChapterBlob(0, of: other.id)
        try await h.library.delete(other.id)
        #expect(try await h.store.document(id: other.id) == nil)
        #expect(!exists(h.paths.documentDirectory(other.id)))
    }
}
