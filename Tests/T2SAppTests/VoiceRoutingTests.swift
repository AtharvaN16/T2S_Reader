import Testing
@testable import T2SApp

@Suite struct VoiceRoutingTests {
    private let identity = "kokoro-4e9ecdf0-mlx-misaki1.0.6"
    private let kokoroVoiceID = "kokoro:kokoro-4e9ecdf0-mlx-misaki1.0.6:af_heart"

    @Test func passthroughReturnsWhatItWasGiven() async {
        let routing = PassthroughVoiceRouting()
        #expect(await routing.effectiveVoiceID(kokoroVoiceID) == kokoroVoiceID)
        #expect(await routing.effectiveVoiceID("default") == "default")
    }

    @Test func aBuildWithoutKokoroFallsBackOnlyForKokoroIDs() async {
        let routing = KokoroVoiceRouting.unavailable
        #expect(await routing.effectiveVoiceID(kokoroVoiceID) == VoiceOption.systemDefault.id)
        #expect(await routing.effectiveVoiceID("system:com.example.voice") == "system:com.example.voice")
        #expect(await routing.effectiveVoiceID("cloud:fp:v") == "cloud:fp:v")
        #expect(await routing.effectiveVoiceID("default") == "default")
    }

    @Test func kokoroIDsRenderWithKokoroOnlyWhenThisBuildHasItAndItIsAvailable() async {
        let available = KokoroVoiceRouting(engineIdentity: identity, isAvailable: { true })
        #expect(await available.effectiveVoiceID(kokoroVoiceID) == kokoroVoiceID)

        let probeFailed = KokoroVoiceRouting(engineIdentity: identity, isAvailable: { false })
        #expect(await probeFailed.effectiveVoiceID(kokoroVoiceID) == VoiceOption.systemDefault.id)

        // Audio from another weights/runtime/G2P identity is not this build's to render (spec §5).
        let otherBuild = KokoroVoiceRouting(engineIdentity: "kokoro-00000000-mlx-misaki1.0.6", isAvailable: { true })
        #expect(await otherBuild.effectiveVoiceID(kokoroVoiceID) == VoiceOption.systemDefault.id)
    }
}
