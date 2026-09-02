import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct PlayheadStoreTests {
    @Test func saveThroughTheProtocolPersistsPositionAndLastPlayed() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let playhead: any PlayheadStore = store
        let p = Position(resourceHref: "ch1.xhtml", progression: 0.25, charOffset: 12, cssSelector: "p:nth-child(3)")
        await playhead.save(p, for: doc.id)
        #expect(try await store.document(id: doc.id)?.resumePosition == p)
        let s = try #require(try await store.summary(id: doc.id))
        #expect(s.lastPlayedAt != nil)
        #expect(abs((s.lastPlayedAt ?? .distantPast).timeIntervalSinceNow) < 5)
    }

    @Test func unknownDocumentIsIgnoredByTheProtocolAndThrownByTheDirectCall() async throws {
        let store = try LibraryStore.inMemory()
        let id = UUID()
        await (store as any PlayheadStore).save(Position(resourceHref: "x", progression: 0), for: id)
        await #expect(throws: LibraryStoreError.documentNotFound(id)) {
            try await store.savePosition(Position(resourceHref: "x", progression: 0), for: id)
        }
    }
}
