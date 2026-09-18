import Foundation
import Testing
@testable import T2SApp

@Suite struct SoundscapeCatalogTests {
    @Test func idsAreUniqueAndRecordingsAreNamedForTheirFiles() {
        let ids = Soundscape.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["rain", "fire", "ocean", "stream", "forest", "night", "brown", "pink"])
        for s in Soundscape.all {
            if case .recording(let resource) = s.source { #expect(resource == "soundscape-\(s.id)") }
        }
        #expect(Soundscape.named("fire")?.title == "Fire")
        #expect(Soundscape.named(nil) == nil && Soundscape.named("bagpipes") == nil)
    }

    /// The manifest the fetch script reads names exactly the recordings the catalogue plays.
    @Test func theManifestAndTheCatalogueAgree() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Soundscapes/soundscapes-manifest.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let recordings = try #require(json?["recordings"] as? [[String: Any]])
        let manifestIDs = Set(recordings.compactMap { $0["id"] as? String })
        let catalogueIDs = Set(Soundscape.all.compactMap { s -> String? in
            if case .recording = s.source { return s.id } else { return nil }
        })
        #expect(manifestIDs == catalogueIDs)
        #expect(recordings.allSatisfy { ($0["licence"] as? String) == "cc0" })
    }
}
