import Foundation
import Testing
@testable import T2SApp

@Suite struct OnboardingManifestTests {
    static let json = """
    {
      "hero": "alice",
      "voices": ["af_heart", "af_bella"],
      "books": [
        {"id": "alice", "title": "Alice", "author": "Lewis Carroll", "voice": "af_heart", "line": "Alice was beginning to get very tired."},
        {"id": "moby-dick", "title": "Moby-Dick", "author": "Herman Melville", "voice": "am_michael", "line": "Call me Ishmael."}
      ]
    }
    """

    @Test func decodesTheBundledShape() throws {
        let manifest = try JSONDecoder().decode(OnboardingManifest.self, from: Data(Self.json.utf8))
        #expect(manifest.hero == "alice")
        #expect(manifest.voices == ["af_heart", "af_bella"])
        #expect(manifest.books.map(\.id) == ["alice", "moby-dick"])
        #expect(manifest.heroBook?.author == "Lewis Carroll")
    }

    /// The hero settles at the end, so it rises last whatever the manifest's order.
    @Test func theHeroRisesLast() throws {
        let manifest = try JSONDecoder().decode(OnboardingManifest.self, from: Data(Self.json.utf8))
        #expect(manifest.risingOrder.map(\.id) == ["moby-dick", "alice"])
    }

    @Test func aMissingHeroStillRisesTheOthers() {
        let manifest = OnboardingManifest(hero: "nowhere", voices: [], books: [
            .init(id: "a", title: "A", author: "", voice: "af_heart", line: ""),
        ])
        #expect(manifest.heroBook == nil)
        #expect(manifest.risingOrder.map(\.id) == ["a"])
    }

    @Test func clipNamesMatchTheRenderScript() {
        #expect(OnboardingManifest.clipName(book: "alice", voice: "af_bella") == "onboarding-alice-af_bella")
        #expect(OnboardingManifest.passageClipName(book: "alice", voice: "af_bella") == "onboarding-alice-passage-af_bella")
    }

    /// Only the hero carries a passage; the others decode without one.
    @Test func thePassageIsOptional() throws {
        let manifest = try JSONDecoder().decode(OnboardingManifest.self, from: Data(Self.json.utf8))
        #expect(manifest.books.allSatisfy { $0.passage == nil })
    }

    @Test func timingsFindTheWordBeingSpoken() throws {
        let timings = OnboardingClipTimings(book: "alice", voice: "af_heart", spoken: "Call me Ishmael.", duration: 1.2, words: [
            .init(start: 0.1, end: 0.3, range: [0, 4]),
            .init(start: 0.35, end: 0.5, range: [5, 7]),
            .init(start: 0.55, end: 1.1, range: [8, 16]),
        ])
        #expect(timings.wordIndex(at: 0) == nil)
        #expect(timings.wordIndex(at: 0.2) == 0)
        #expect(timings.wordIndex(at: 0.52) == 1)   // between words: the last one that started
        #expect(timings.wordIndex(at: 2) == 2)
    }

    @Test func timingsRoundTripTheProbeFormat() throws {
        let data = Data("""
        {"book":"alice","voice":"af_heart","spoken":"Call me Ishmael.","duration":1.2,
         "words":[{"start":0.1,"end":0.3,"range":[0,4]}]}
        """.utf8)
        let timings = try JSONDecoder().decode(OnboardingClipTimings.self, from: data)
        #expect(timings.words.count == 1)
        #expect(timings.words[0].range == [0, 4])
    }
}
