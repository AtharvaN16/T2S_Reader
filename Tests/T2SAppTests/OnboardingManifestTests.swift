import Foundation
import Testing
@testable import T2SApp

@Suite struct OnboardingManifestTests {
    static let json = """
    {
      "hero": "alice",
      "voices": ["af_heart", "af_bella"],
      "books": [
        {"id": "alice", "title": "Alice", "author": "Lewis Carroll", "standardEbooks": "lewis-carroll/alice", "passage": "Alice was beginning to get very tired."},
        {"id": "moby-dick", "title": "Moby-Dick", "author": "Herman Melville", "voice": "am_michael", "line": "Call me Ishmael."},
        {"id": "dracula", "title": "Dracula", "author": "Bram Stoker"},
        {"id": "jane-eyre", "title": "Jane Eyre", "author": "Charlotte Brontë", "voice": "af_sarah", "line": "There was no possibility of taking a walk that day."}
      ]
    }
    """

    func manifest() throws -> OnboardingManifest {
        try JSONDecoder().decode(OnboardingManifest.self, from: Data(Self.json.utf8))
    }

    @Test func decodesTheBundledShape() throws {
        let manifest = try manifest()
        #expect(manifest.hero == "alice")
        #expect(manifest.voices == ["af_heart", "af_bella"])
        #expect(manifest.books.map(\.id) == ["alice", "moby-dick", "dracula", "jane-eyre"])
        #expect(manifest.heroBook?.author == "Lewis Carroll")
        #expect(manifest.heroBook?.standardEbooks == "lewis-carroll/alice")
    }

    /// A book with a line and a voice speaks; one with neither only floats; the hero never speaks
    /// on the way up even if it had a line.
    @Test func onlyBooksWithALineAndAVoiceAreVoiced() throws {
        let manifest = try manifest()
        #expect(manifest.voiced.map(\.id) == ["moby-dick", "jane-eyre"])
        var withTalkingHero = manifest
        withTalkingHero.books[0].voice = "af_heart"
        withTalkingHero.books[0].line = "Alice."
        #expect(withTalkingHero.voiced.map(\.id) == ["moby-dick", "jane-eyre"])
    }

    /// The voiced books rise in order and the hero last, whatever the manifest's order.
    @Test func theHeroRisesLast() throws {
        #expect(try manifest().risingOrder.map(\.id) == ["moby-dick", "jane-eyre", "alice"])
    }

    /// The crowd is everything that is not rising, so a cover never floats past itself.
    @Test func theCrowdIsTheRest() throws {
        #expect(try manifest().crowd.map(\.id) == ["dracula"])
    }

    @Test func aMissingHeroStillRisesTheOthers() {
        let manifest = OnboardingManifest(hero: "nowhere", voices: [], books: [
            .init(id: "a", title: "A", author: "", voice: "af_heart", line: "A."),
        ])
        #expect(manifest.heroBook == nil)
        #expect(manifest.risingOrder.map(\.id) == ["a"])
        #expect(manifest.crowd.isEmpty)
    }

    @Test func fileNamesMatchTheScripts() {
        #expect(OnboardingManifest.clipName(book: "alice", voice: "af_bella") == "onboarding-alice-af_bella")
        #expect(OnboardingManifest.passageClipName(book: "alice", voice: "af_bella") == "onboarding-alice-passage-af_bella")
        #expect(OnboardingManifest.Book(id: "moby-dick", title: "", author: "").coverName == "onboarding-cover-moby-dick.jpg")
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
