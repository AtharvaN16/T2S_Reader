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

    // MARK: Several routes, and Kokoro Heart as the default voice

    private let coreMLIdentity = "kokoro-coreml-2e878c6a-misaki1.0.6"
    private let coreMLVoiceID = "kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart"

    private func routing(coreML: Bool, mlx: Bool, defaultVoice: String?) -> KokoroVoiceRouting {
        KokoroVoiceRouting(
            routes: [
                .init(engineIdentity: coreMLIdentity, isAvailable: { coreML }),
                .init(engineIdentity: identity, isAvailable: { mlx }),
            ],
            defaultVoice: defaultVoice
        )
    }

    @Test func theSystemDefaultBecomesTheKokoroDefaultVoiceWhenItsRouteIsAvailable() async {
        let routing = routing(coreML: true, mlx: false, defaultVoice: coreMLVoiceID)
        #expect(await routing.effectiveVoiceID("default") == coreMLVoiceID)
        #expect(await routing.effectiveVoiceID(VoiceOption.systemDefault.id) == coreMLVoiceID)
    }

    @Test func theSystemDefaultStaysItselfWhenTheDefaultVoicesRouteIsNotAvailable() async {
        let probeFailed = routing(coreML: false, mlx: true, defaultVoice: coreMLVoiceID)
        #expect(await probeFailed.effectiveVoiceID("default") == VoiceOption.systemDefault.id)
        #expect(await probeFailed.effectiveVoiceID(VoiceOption.systemDefault.id) == VoiceOption.systemDefault.id)

        // A default voice whose identity is not routed at all is the same situation.
        let unrouted = KokoroVoiceRouting(routes: [], defaultVoice: coreMLVoiceID)
        #expect(await unrouted.effectiveVoiceID("default") == VoiceOption.systemDefault.id)

        // And with no default voice, "default" means what it has always meant.
        let noDefault = routing(coreML: true, mlx: true, defaultVoice: nil)
        #expect(await noDefault.effectiveVoiceID("default") == VoiceOption.systemDefault.id)
    }

    @Test func eachKokoroIdentityIsRoutedByItsOwnAvailability() async {
        let coreMLOnly = routing(coreML: true, mlx: false, defaultVoice: coreMLVoiceID)
        #expect(await coreMLOnly.effectiveVoiceID(coreMLVoiceID) == coreMLVoiceID)

        let mlxOnly = routing(coreML: false, mlx: true, defaultVoice: coreMLVoiceID)
        #expect(await mlxOnly.effectiveVoiceID(kokoroVoiceID) == kokoroVoiceID)
        // Core ML is down, and the default voice needs it, so there is nothing left but the system.
        #expect(await mlxOnly.effectiveVoiceID(coreMLVoiceID) == VoiceOption.systemDefault.id)
    }

    /// The identity travels in the voice ID so that a revision bump re-routes old documents to the
    /// *new* default voice, not to the system voice; a runtime that cannot run on this phone is the
    /// same situation seen from the other side.
    @Test func anUnroutableKokoroVoiceFallsBackToTheDefaultVoiceNotTheSystemVoice() async {
        let coreMLUp = routing(coreML: true, mlx: false, defaultVoice: coreMLVoiceID)
        // An MLX voice on a phone that cannot run MLX speaks with Core ML's Heart.
        #expect(await coreMLUp.effectiveVoiceID(kokoroVoiceID) == coreMLVoiceID)
        // As does a document stored against an identity this build no longer routes at all.
        #expect(await coreMLUp.effectiveVoiceID("kokoro:kokoro-00000000-coreml-misaki1.0.6:af_heart")
                == coreMLVoiceID)

        // With every route down there is no Kokoro to fall back to, so it is the system voice.
        let allDown = routing(coreML: false, mlx: false, defaultVoice: coreMLVoiceID)
        #expect(await allDown.effectiveVoiceID(kokoroVoiceID) == VoiceOption.systemDefault.id)
        #expect(await allDown.effectiveVoiceID(coreMLVoiceID) == VoiceOption.systemDefault.id)

        // And in a build with no routes and no default voice — the everyday one — likewise.
        #expect(await KokoroVoiceRouting.unavailable.effectiveVoiceID(kokoroVoiceID)
                == VoiceOption.systemDefault.id)
    }

    @Test func anIdentityWithNoRouteFallsBackAndOtherRoutesAreLeftAlone() async {
        let routing = routing(coreML: true, mlx: true, defaultVoice: coreMLVoiceID)
        #expect(await routing.effectiveVoiceID("kokoro:kokoro-00000000-coreml-misaki1.0.6:af_heart")
                == coreMLVoiceID)
        #expect(await routing.effectiveVoiceID("system:com.example.voice") == "system:com.example.voice")
        #expect(await routing.effectiveVoiceID("cloud:fp:v") == "cloud:fp:v")
    }
}
