import os
import Testing
import T2SAudio
@testable import T2SApp

@Suite struct KokoroVoiceCatalogTests {
    private let identity = "kokoro-4e9ecdf0-mlx-misaki1.0.6"

    @Test func withOneEngineTheListIsTwentyEightKokoroOnlyRows() throws {
        let catalog = KokoroVoiceCatalog(base: BaseCatalog(), engineIdentity: identity)
        let voices = catalog.voices()

        // One "Default" row leads — the only way left to mean "no override" — then the 28 voices.
        #expect(voices.count == 29)
        #expect(voices.first == KokoroVoiceCatalog.defaultRow)
        #expect(voices.first?.id == VoiceOption.systemDefault.id)
        let kokoro = Array(voices.dropFirst())
        #expect(voices.allSatisfy { $0.group == .kokoro })
        #expect(kokoro.map(\.id) == KokoroVoiceCatalog.voiceNames.map {
            KokoroVoiceID(engineID: identity, voice: $0).rawValue
        })
        for option in kokoro {
            let parsed = try #require(KokoroVoiceID(rawValue: option.id))
            #expect(parsed.engineID == identity)
        }

        // The second line is the voice's character; accent and gender ride separately, as the
        // sub-section (`language`) and the avatar tint (`gender`), so neither is repeated in words.
        let heart = try #require(kokoro.first)
        #expect(heart.name == "Heart")
        #expect(heart.detail == "Warm, Breathy and Intimate")
        #expect(heart.language == "en-US")
        #expect(heart.gender == .female)

        let emma = try #require(voices.first { KokoroVoiceID(rawValue: $0.id)?.voice == "bf_emma" })
        #expect(emma.name == "Emma")
        #expect(emma.detail == "Polished, Warm and Inviting")
        #expect(emma.language == "en-GB")
        #expect(emma.gender == .female)

        let george = try #require(voices.first { KokoroVoiceID(rawValue: $0.id)?.voice == "bm_george" })
        #expect(george.detail == "Distinguished, Articulate and Reassuring")
        #expect(george.gender == .male)
        #expect(voices.first?.gender == nil)   // the "Default" pointer row has no tint
    }

    @Test func everyVoiceHasItsOwnPersonalityLineAndAGender() {
        let catalog = KokoroVoiceCatalog(base: BaseCatalog(), engineIdentity: identity)
        let kokoro = catalog.voices().dropFirst()
        #expect(Set(KokoroVoiceCatalog.personalities.keys) == Set(KokoroVoiceCatalog.voiceNames))
        #expect(kokoro.allSatisfy { $0.gender != nil })
        #expect(kokoro.allSatisfy { !($0.detail ?? "").contains("·") })
        #expect(Set(kokoro.compactMap(\.detail)).count == kokoro.count)   // no two voices read alike
    }

    @Test func withNoEnginesTheBaseRowsIncludingSystemDefaultPassThroughUnchanged() {
        let base = BaseCatalog()
        let catalog = KokoroVoiceCatalog(base: base, engines: [])
        #expect(catalog.voices() == base.voices())
    }

    @Test func aCloudRowInTheBaseSurvivesTheFilterWhileSystemRowsAreHidden() {
        let cloud = VoiceOption(id: "cloud:fp:v", name: "Astra · Cloud", language: "Cloud", group: .cloud)
        let base = BaseCatalog(extra: [cloud])
        let catalog = KokoroVoiceCatalog(base: base, engineIdentity: identity)
        let voices = catalog.voices()

        #expect(voices.count == 30)
        #expect(!voices.contains { $0.group == .system })
        #expect(voices.first?.isDefault == true)
        #expect(voices.contains(cloud))
    }

    @Test func everyLinkedEngineListsAllTwentyEightVoicesAndOnlyALabelledOneSaysSo() throws {
        let coreML = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let catalog = KokoroVoiceCatalog(base: BaseCatalog(), engines: [(coreML, ""), (identity, "MLX")])
        let voices = catalog.voices()

        #expect(voices.count == 57)
        #expect(!voices.contains { $0.group == .system })
        let kokoro = Array(voices.dropFirst())   // past the "Default" row
        // The default route leads, so the picker's first Kokoro row is the one the reader gets by
        // default (spec §2.2).
        #expect(kokoro.prefix(28).allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == coreML })
        #expect(kokoro.dropFirst(28).allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == identity })

        // The label is a runtime qualifier: the everyday route reads as it always has, and only the
        // second runtime has to name itself to be told apart.
        #expect(kokoro.first?.name == "Heart")
        #expect(kokoro.first?.detail == "Warm, Breathy and Intimate")
        #expect(kokoro.dropFirst(28).first?.name == "Heart")
        #expect(kokoro.dropFirst(28).first?.detail == "Warm, Breathy and Intimate · MLX")
        let mlxEmma = try #require(kokoro.dropFirst(28).first { KokoroVoiceID(rawValue: $0.id)?.voice == "bf_emma" })
        #expect(mlxEmma.detail == "Polished, Warm and Inviting · MLX")
        #expect(mlxEmma.language == "en-GB")
        #expect(voices.allSatisfy { $0.group == .kokoro })
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

        let beforeTheProbe = Array(catalog.voices().dropFirst())   // past the "Default" row
        #expect(beforeTheProbe.count == 28)
        #expect(beforeTheProbe.allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == coreML })

        mlxAvailable.withLock { $0 = true }

        let afterTheProbe = Array(catalog.voices().dropFirst())
        #expect(afterTheProbe.count == 56)
        #expect(afterTheProbe.dropFirst(28).allSatisfy { KokoroVoiceID(rawValue: $0.id)?.engineID == mlx })
        #expect(afterTheProbe.dropFirst(28).first?.detail == "Warm, Breathy and Intimate · MLX")
    }
}

private struct BaseCatalog: VoiceCatalog {
    var extra: [VoiceOption] = []
    func voices() -> [VoiceOption] { [.systemDefault] + extra }
}
