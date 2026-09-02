import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SLibrary

@Suite struct LibraryTests {
    struct Harness {
        let library: Library
        let paths: LibraryPaths
        let store: LibraryStore
        let audio: InMemoryAudioStore
    }

    func makeHarness(readers: [any DocumentReader]) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-lib-\(UUID().uuidString)")
        let paths = LibraryPaths(root: root)
        let store = try LibraryStore.inMemory()
        let audio = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let library = Library(paths: paths, store: store, audioStore: audio, readers: readers)
        return Harness(library: library, paths: paths, store: store, audio: audio)
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
        #expect(await h.audio.contains(oldKey) == false)                    // orphan removed
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
        let reprocessed = try await h.library.reprocess(doc.id)
        #expect(reprocessed[utterance: 2].spoken == "3rd sentence.")
        #expect(try await h.store.timeline(for: doc.id)?.timeline == reprocessed)
    }
}
