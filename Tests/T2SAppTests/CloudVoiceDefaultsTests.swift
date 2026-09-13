import Foundation
import Testing
import T2SAudio
@testable import T2SApp

@Suite struct CloudVoiceDefaultsTests {
    @Test func theShippedRouteIsTheSevenMirrors() throws {
        let configuration = try CloudVoiceDefaults.pilot.configuration()
        #expect(configuration.endpoints.count == 7)
        #expect(configuration.endpoint.host == "kokoro-t2s-a007171ff076.herokuapp.com")
        #expect(configuration.model == "kokoro" && configuration.voice == "af_heart")
        #expect(configuration.requestRatePerMinute == 20)
    }

    @Test func theShippedRouteIsSelectableAsOneCloudVoice() throws {
        let store = CloudVoiceConfigurationStore(configuration: try CloudVoiceDefaults.pilot.configuration())
        let ids = CloudVoiceCatalog(base: StaticCatalog(), configurationStore: store).voices().map(\.id)
        #expect(ids.filter { $0.hasPrefix("cloud:") }.count == 1)
    }

    @Test func oneEndpointPerLineTheFirstBeingThePrimary() throws {
        let defaults = CloudVoiceDefaults(
            endpointText: " https://one.example/v1/audio/speech \n\nhttps://two.example/v1/audio/speech\nhttps://three.example/v1/audio/speech\n",
            model: "m", voice: "v", requestRatePerMinute: 20
        )
        let configuration = try defaults.configuration()
        #expect(configuration.endpoints.map(\.host) == ["one.example", "two.example", "three.example"])
        #expect(configuration.endpoint.host == "one.example")
    }

    /// Adding a mirror keeps the route's identity, so nothing already rendered is thrown away.
    @Test func aMirrorKeepsTheRouteIdentity() throws {
        var defaults = CloudVoiceDefaults(endpointText: "https://one.example/v1/audio/speech",
                                          model: "m", voice: "v", requestRatePerMinute: 20)
        let alone = try defaults.configuration().fingerprint
        defaults.endpointText += "\nhttps://two.example/v1/audio/speech"
        #expect(try defaults.configuration().fingerprint == alone)
    }

    @Test func aBadMirrorLineInvalidatesTheRoute() {
        let defaults = CloudVoiceDefaults(
            endpointText: "https://one.example/v1/audio/speech\nhttp://two.example/v1/audio/speech",
            model: "m", voice: "v", requestRatePerMinute: 20
        )
        #expect(throws: HTTPVoiceError.invalidConfiguration) { try defaults.configuration() }
    }

    @Test func noEndpointIsNoRoute() {
        let defaults = CloudVoiceDefaults(endpointText: "\n  \n", model: "m", voice: "v", requestRatePerMinute: 20)
        #expect(throws: HTTPVoiceError.invalidConfiguration) { try defaults.configuration() }
    }
}

private struct StaticCatalog: VoiceCatalog {
    func voices() -> [VoiceOption] { [.systemDefault] }
}
