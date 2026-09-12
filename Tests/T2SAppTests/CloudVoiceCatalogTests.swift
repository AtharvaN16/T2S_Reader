import Foundation
import Testing
import T2SAudio
@testable import T2SApp

@Suite struct CloudVoiceCatalogTests {
    private struct EmptyCatalog: VoiceCatalog {
        func voices() -> [VoiceOption] { [] }
    }

    private func hosted(model: String, voice: String) throws -> VoiceOption {
        let configuration = HTTPVoiceConfiguration(endpoint: try #require(URL(string: "https://voice.example/v1/audio/speech")),
                                                   model: model, voice: voice, requestRatePerMinute: 60)
        let catalog = CloudVoiceCatalog(base: EmptyCatalog(), configurationStore: CloudVoiceConfigurationStore(configuration: configuration))
        return try #require(catalog.voices().last)
    }

    /// The hosted Heart is the same voice as the on-device one, so it wears the same name and
    /// character; only the suffix says where it renders.
    @Test func aHostedKokoroVoiceIsNamedLikeTheOnDeviceOne() throws {
        let heart = try hosted(model: "kokoro", voice: "af_heart")
        #expect(heart.name == "Heart · Cloud")
        #expect(heart.detail == KokoroVoiceCatalog.personalities["af_heart"])
        #expect(heart.group == .cloud)
    }

    @Test func anotherProvidersVoiceKeepsItsOwnName() throws {
        let alloy = try hosted(model: "gpt-4o-mini-tts", voice: "alloy")
        #expect(alloy.name == "alloy · Cloud")
        #expect(alloy.detail == nil)
    }
}
