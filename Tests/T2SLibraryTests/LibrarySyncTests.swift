// Tests/T2SLibraryTests/LibrarySyncTests.swift
import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SLibrary

@Suite struct LibrarySyncTests {
    /// A library over an in-memory store and a temporary root, reading through `FakeDocumentReader`
    /// (the test target's stub; it claims every source type and yields two fixed chapters) — the
    /// same harness `LibraryTests.makeHarness` builds.
    private func makeLibrary() throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-sync-\(UUID().uuidString)")
        return Library(paths: LibraryPaths(root: root), store: try LibraryStore.inMemory(),
                       audioStore: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000),
                       readers: [FakeDocumentReader()], segmenterPackLength: 0)
    }

    /// Sync spec §5: an article the other device has is a placeholder; importing it here — by its
    /// URL — fills that row rather than adding a second document, and the position waits on it.
    @Test func importingAnArticleFillsItsPlaceholder() async throws {
        let library = try makeLibrary()
        let url = URL(string: "https://Example.com/story?utm_source=mail")!
        let key = ContentKey.article(url)
        try await library.store.writeSynced(
            SyncedDocument(contentKey: key, title: "Story", sourceType: .article, sourceURL: url, addedAt: Date(timeIntervalSince1970: 1),
                           resume: SyncedPosition(position: Position(resourceHref: "chapter1.xhtml", progression: 0.5),
                                                  savedAt: Date(timeIntervalSince1970: 2), deviceName: "iPad"),
                           updatedAt: Date(timeIntervalSince1970: 2)),
            offering: nil)
        let placeholder = try #require(try await library.store.placeholder(contentKey: key))

        let article = ArticleContent(title: "Story", sourceURL: url, bodyXHTML: "<p>Once upon a time. The end.</p>")
        let result = try await library.importArticle(article, originalHTML: "<html>…</html>")

        #expect(result.document.id == placeholder)
        #expect(result.document.contentKey == key)
        #expect(try await library.store.placeholder(contentKey: key) == nil)
        #expect(try await library.store.documents().count == 1)
        #expect(try await library.store.document(id: placeholder)?.resumePosition?.progression == 0.5)
    }

    /// A file that is not the placeholder's is refused before anything is imported.
    @Test func fillingAPlaceholderWithTheWrongFileIsRefused() async throws {
        let library = try makeLibrary()
        try await library.store.writeSynced(SyncedDocument(contentKey: "sha256:not-these-bytes", title: "Book", sourceType: .epub,
                                                           addedAt: Date(), updatedAt: Date()), offering: nil)
        let placeholder = try #require(try await library.store.placeholder(contentKey: "sha256:not-these-bytes"))
        let file = FileManager.default.temporaryDirectory.appending(path: "wrong-\(UUID().uuidString).epub")
        try Data("zip".utf8).write(to: file)
        await #expect(throws: ImportError.differentFile) {
            try await library.fillPlaceholder(placeholder, from: file, sourceType: .epub)
        }
        #expect(try await library.store.documents().count == 1)

        // A document that is not a placeholder at all is refused too — even if `fillPlaceholder`
        // were only checking `contentKey`, this id has none of the placeholder's identity.
        let real = try await library.importArticle(
            ArticleContent(title: "Real", sourceURL: URL(string: "https://x.y/real")!, bodyXHTML: "<p>Text.</p>"),
            originalHTML: "")
        let anyFile = FileManager.default.temporaryDirectory.appending(path: "any-\(UUID().uuidString).epub")
        try Data("zip".utf8).write(to: anyFile)
        await #expect(throws: (any Error).self) {
            try await library.fillPlaceholder(real.document.id, from: anyFile, sourceType: .epub)
        }
        #expect(try await library.store.documents().count == 2)
    }
}
