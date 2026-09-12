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

    @Test func oneEndpointPerLineTheFirstBeingThePrimary() async throws {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = " https://one.example/v1/audio/speech \n\nhttps://two.example/v1/audio/speech\nhttps://three.example/v1/audio/speech\n"
        settings.model = "m"
        settings.voice = "v"
        try await settings.save()

        let configuration = try #require(settings.configurationStore.current())
        #expect(configuration.endpoints.map(\.host) == ["one.example", "two.example", "three.example"])
        #expect(configuration.endpoint.host == "one.example")
    }

    /// Adding a mirror keeps the route's identity, so nothing already rendered is thrown away.
    @Test func aMirrorEditKeepsTheRouteIdentity() throws {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = "https://one.example/v1/audio/speech"
        settings.model = "m"
        settings.voice = "v"
        let alone = try #require(settings.cloudVoiceID)
        settings.endpointText += "\nhttps://two.example/v1/audio/speech"
        #expect(settings.cloudVoiceID == alone)
    }

    @Test func aBadMirrorLineInvalidatesTheRoute() async {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = "https://one.example/v1/audio/speech\nhttp://two.example/v1/audio/speech"
        settings.model = "m"
        settings.voice = "v"
        await #expect(throws: HTTPVoiceError.invalidConfiguration) { try await settings.save() }
        #expect(settings.cloudVoiceID == nil)
    }

    @Test func shippedDefaultsAreWrittenOnceIntoEmptySettings() throws {
        let settings = CloudVoiceSettings(defaults: freshDefaults(), shipped: .pilot)
        #expect(settings.endpointText == CloudVoiceDefaults.pilot.endpointText)
        #expect(settings.model == "kokoro" && settings.voice == "af_heart" && settings.requestRatePerMinute == 20)
        let configuration = try #require(settings.configurationStore.current())
        #expect(configuration.endpoints.count == 7)
        #expect(settings.cloudVoiceID?.hasPrefix("cloud:") == true)
    }

    /// The reader's edit wins, even an edit to nothing: the shipped route is a first-launch value,
    /// never a reset.
    @Test func aStoredEndpointIsNeverOverwrittenByTheShippedOne() {
        let defaults = freshDefaults()
        let first = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        first.endpointText = ""
        let again = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        #expect(again.endpointText == "")
        #expect(again.configurationStore.current() == nil)
    }

    @Test func noShippedDefaultsLeaveTheSettingsEmpty() {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        #expect(settings.endpointText == "" && settings.configurationStore.current() == nil)
    }

    /// A route the app wrote itself, untouched, follows the build: a phone first launched with the
    /// four-mirror route takes the seven-mirror one on the next launch.
    @Test func anUneditedShippedRouteFollowsTheBuild() throws {
        let defaults = freshDefaults()
        let earlier = CloudVoiceDefaults(endpointText: CloudVoiceDefaults.superseded[0], model: "kokoro", voice: "af_heart", requestRatePerMinute: 20)
        _ = CloudVoiceSettings(defaults: defaults, shipped: earlier)
        let upgraded = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        #expect(upgraded.endpointText == CloudVoiceDefaults.pilot.endpointText)
        #expect(try #require(upgraded.configurationStore.current()).endpoints.count == 7)
    }

    /// The four-URL route this phone's first launch stored predates the marker, so it is known by
    /// value: it is upgraded too.
    @Test func theRouteAnEarlierBuildStoredWithoutAMarkerIsUpgradedByValue() throws {
        let defaults = freshDefaults()
        defaults.set(CloudVoiceDefaults.superseded[0], forKey: "cloudVoice.endpoint")
        defaults.set("kokoro", forKey: "cloudVoice.model")
        defaults.set("af_heart", forKey: "cloudVoice.voice")
        let upgraded = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        #expect(try #require(upgraded.configurationStore.current()).endpoints.count == 7)
    }

    /// An edit is the reader's: a route that differs from anything the app shipped is left alone.
    @Test func anEditedRouteIsNeverUpgraded() {
        let defaults = freshDefaults()
        _ = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        let edited = CloudVoiceSettings(defaults: defaults)
        edited.endpointText = "https://mine.example/v1/audio/speech"
        let later = CloudVoiceSettings(defaults: defaults, shipped: .pilot)
        #expect(later.endpointText == "https://mine.example/v1/audio/speech")
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
