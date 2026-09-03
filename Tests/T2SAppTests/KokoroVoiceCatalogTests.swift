import Testing
import T2SAudio
@testable import T2SApp

@Suite struct KokoroVoiceCatalogTests {
    private let identity = "kokoro-4e9ecdf0-mlx-misaki1.0.6"

    @Test func appendsTheBundledVoicesAfterTheBaseCatalogUnderThisBuildsIdentity() throws {
        let catalog = KokoroVoiceCatalog(base: BaseCatalog(), engineIdentity: identity)
        let voices = catalog.voices()

        #expect(voices.first == .systemDefault)
        let kokoro = Array(voices.dropFirst())
        #expect(kokoro.count == 28)
        #expect(kokoro.allSatisfy { $0.group == .kokoro })
        #expect(kokoro.map(\.id) == KokoroVoiceCatalog.voiceNames.map {
            KokoroVoiceID(engineID: identity, voice: $0).rawValue
        })
        for option in kokoro {
            let parsed = try #require(KokoroVoiceID(rawValue: option.id))
            #expect(parsed.engineID == identity)
        }
    }

    @Test func namesAndLanguagesReadAsAPickerRow() throws {
        let kokoro = Array(KokoroVoiceCatalog(base: BaseCatalog(), engineIdentity: identity).voices().dropFirst())

        let heart = try #require(kokoro.first)
        #expect(heart.name == "Heart · en-US")
        #expect(heart.language == "en-US")

        let emma = try #require(kokoro.first { KokoroVoiceID(rawValue: $0.id)?.voice == "bf_emma" })
        #expect(emma.name == "Emma · en-GB")
        #expect(emma.language == "en-GB")
    }
}

private struct BaseCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] { [.systemDefault] }
}
