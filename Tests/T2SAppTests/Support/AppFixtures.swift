import Foundation
import T2SCore
import T2SLibrary
import T2SStore

struct AppFixtures {
    let paths: LibraryPaths
    let store: LibraryStore
    let audio: InMemoryAudioStore
    let library: Library

    init(readers: [any DocumentReader] = [FakeReader()]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-app-\(UUID().uuidString)")
        paths = LibraryPaths(root: root)
        store = try LibraryStore.inMemory()
        audio = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 50_000_000)
        library = Library(paths: paths, store: store, audioStore: audio, readers: readers)
    }

    /// Imports a placeholder EPUB through `FakeReader` and returns the new document's id.
    func importFake() async throws -> UUID {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).epub")
        try Data("PK".utf8).write(to: file)
        return try await library.importFile(at: file, sourceType: .epub).document.id
    }
}
