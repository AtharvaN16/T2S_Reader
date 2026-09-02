import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct PronunciationTests {
    @Test func upsertListDelete() async throws {
        let store = try LibraryStore.inMemory()
        let kokoro = PronunciationEntry(term: "Kokoro", replacement: "koh-koh-roh")
        let nginx = PronunciationEntry(term: "nginx", replacement: "engine x", caseSensitive: true)
        try await store.upsert(nginx)
        try await store.upsert(kokoro)
        #expect(try await store.pronunciations() == [kokoro, nginx])        // sorted by term, case-insensitively
        var edited = kokoro
        edited.replacement = "ko-ko-ro"
        try await store.upsert(edited)
        #expect(try await store.pronunciations() == [edited, nginx])
        try await store.deletePronunciation(id: nginx.id)
        #expect(try await store.pronunciations() == [edited])
        try await store.deletePronunciation(id: UUID())                     // unknown: no-op
    }
}
