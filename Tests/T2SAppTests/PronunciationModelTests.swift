import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct PronunciationModelTests {
    @Test func saveListEditDelete() async throws {
        let f = try AppFixtures()
        let model = PronunciationModel(store: f.store)
        await model.refresh()
        #expect(model.entries.isEmpty)
        await model.save(term: "nginx", replacement: "engine x", caseSensitive: true, id: nil)
        await model.save(term: "Kokoro", replacement: "ko-ko-ro", caseSensitive: false, id: nil)
        #expect(model.entries.map(\.term) == ["Kokoro", "nginx"])
        let id = model.entries[0].id
        await model.save(term: "Kokoro", replacement: "koh-koh-roh", caseSensitive: false, id: id)
        #expect(model.entries.first { $0.id == id }?.replacement == "koh-koh-roh")
        await model.save(term: "   ", replacement: "x", caseSensitive: false, id: nil)
        #expect(model.entries.count == 2)
        await model.delete(id: id)
        #expect(model.entries.map(\.term) == ["nginx"])
        #expect(model.lastError == nil)
    }
}
