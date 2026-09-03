import Foundation
import Testing
import T2SAudio
@testable import T2SApp

@MainActor
@Suite struct CloudVoiceSettingsTests {
    @Test func persistsOnlyNonSecretSettingsAndChangesTheRoutedVoiceIdentity() async throws {
        let defaults = freshDefaults()
        let settings = CloudVoiceSettings(defaults: defaults)
        let secrets = InMemorySecretStore()
        settings.endpointText = "https://voice.example/v1/audio/speech"
        settings.model = "model-a"
        settings.voice = "voice-a"
        settings.requestRatePerMinute = 37
        try await settings.save()
        try secrets.save("test-key")

        #expect(try secrets.load() == "test-key")
        #expect(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("test-key") } == false)

        let reloaded = CloudVoiceSettings(defaults: defaults)
        #expect(reloaded.endpointText == "https://voice.example/v1/audio/speech")
        #expect(reloaded.model == "model-a" && reloaded.voice == "voice-a")
        #expect(reloaded.requestRatePerMinute == 37)

        let firstID = try #require(settings.cloudVoiceID)
        #expect(!firstID.contains("test-key"))
        #expect(CloudVoiceCatalog(base: StaticCatalog(), configurationStore: settings.configurationStore).voices().map(\.id).contains(firstID))
        settings.model = "model-b"
        #expect(try #require(settings.cloudVoiceID) != firstID)
        settings.model = "model-a"
        settings.endpointText = "https://other.example/v1/audio/speech"
        #expect(try #require(settings.cloudVoiceID) != firstID)
        settings.endpointText = "https://voice.example/v1/audio/speech"
        settings.voice = "voice-b"
        #expect(try #require(settings.cloudVoiceID) != firstID)
    }

    @Test func invalidValuesCannotEnableTheCloudRoute() async {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = "http://voice.example"
        settings.model = ""
        settings.voice = ""

        await #expect(throws: HTTPVoiceError.invalidConfiguration) {
            try await settings.save()
        }
        #expect(settings.cloudVoiceID == nil)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "t2s-cloud-voice-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct StaticCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] { [.systemDefault] }
}
