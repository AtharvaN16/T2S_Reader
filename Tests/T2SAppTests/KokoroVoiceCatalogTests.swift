import os
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

    @Test func everyLinkedEngineListsAllTwentyEightVoicesAndOnlyALabelledOneSaysSo() throws {
        let coreML = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let catalog = KokoroVoiceCatalog(base: BaseCatalog(), engines: [(coreML, ""), (identity, "MLX")])
        let voices = catalog.voices()

        #expect(voices.first == .systemDefault)
        let kokoro = Array(voices.dropFirst())
        #expect(kokoro.count == 56)
        // The default route leads, so the picker's first Kokoro row is the one the reader gets by
        // default (spec §2.2).
        #expect(kokoro.prefix(28).allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == coreML })
        #expect(kokoro.dropFirst(28).allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == identity })

        // The label is a runtime qualifier: the everyday route reads as it always has, and only the
        // second runtime has to name itself to be told apart.
        #expect(kokoro.first?.name == "Heart · en-US")
        #expect(kokoro.dropFirst(28).first?.name == "Heart · en-US · MLX")
        let mlxEmma = try #require(kokoro.dropFirst(28).first { KokoroVoiceID(rawValue: $0.id)?.voice == "bf_emma" })
        #expect(mlxEmma.name == "Emma · en-GB · MLX")
        #expect(mlxEmma.language == "en-GB")
        #expect(kokoro.allSatisfy { $0.group == .kokoro })
    }

    /// A runtime whose availability probe answers after the catalog was built must still reach the
    /// picker: the list is asked for on every draw, not fixed when the composition root wired it.
    @Test func listsARuntimeAsSoonAsItsProbeAnswers() throws {
        let mlx = identity
        let coreML = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let mlxAvailable = OSAllocatedUnfairLock(initialState: false)
        let catalog = KokoroVoiceCatalog(base: BaseCatalog()) {
            var engines: [(identity: String, label: String)] = [(coreML, "")]
            if mlxAvailable.withLock({ $0 }) { engines.append((mlx, "MLX")) }
            return engines
        }

        let beforeTheProbe = Array(catalog.voices().dropFirst())
        #expect(beforeTheProbe.count == 28)
        #expect(beforeTheProbe.allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == coreML })

        mlxAvailable.withLock { $0 = true }

        let afterTheProbe = Array(catalog.voices().dropFirst())
        #expect(afterTheProbe.count == 56)
        #expect(afterTheProbe.dropFirst(28).allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == mlx })
        #expect(afterTheProbe.dropFirst(28).first?.name == "Heart · en-US · MLX")
    }
}

private struct BaseCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] { [.systemDefault] }
}
