import Foundation
import Testing
import T2SCore
@testable import T2SKokoro

@Suite struct KokoroRuntimeDecisionTests {
    /// A decision whose every field is valid. Each test overrides the one field it makes wrong, so a
    /// failure names the rule that was broken rather than the first rule that happened to fire.
    static func decision(
        modelSHA256: String = KokoroResources.modelSHA256,
        voicesSHA256: String = KokoroResources.voicesSHA256,
        measuredRTF: Double = 0.35,
        peakFootprintBytes: Int = 400 * 1024 * 1024,
        gpuCacheLimitBytes: Int = 96 * 1024 * 1024,
        source: String = "spikes/findings/2026-09-03-runtime-benchmark.md"
    ) throws -> KokoroRuntimeDecision {
        try KokoroRuntimeDecision(
            modelSHA256: modelSHA256,
            voicesSHA256: voicesSHA256,
            runtime: "mlx",
            packagePins: "kokoro-ios 1.0.11, mlx-swift 0.30.2, MisakiSwift 1.0.6, MLXUtilsLibrary 0.0.6",
            measuredRTF: measuredRTF,
            peakFootprintBytes: peakFootprintBytes,
            gpuCacheLimitBytes: gpuCacheLimitBytes,
            backgroundInferencePermitted: false,
            idleInferencePermitted: false,
            source: source,
            isDebugOverride: false
        )
    }

    // MARK: Values that are not measurements

    @Test(arguments: [Double.nan, 0, -1, .infinity])
    func rejectsARealTimeFactorThatIsNotAMeasurement(rtf: Double) {
        #expect(throws: KokoroRuntimeDecision.Invalid.rtf) { try Self.decision(measuredRTF: rtf) }
    }

    @Test func rejectsAFootprintOfNothing() {
        #expect(throws: KokoroRuntimeDecision.Invalid.footprint) { try Self.decision(peakFootprintBytes: 0) }
    }

    @Test func rejectsACacheLimitOfNothing() {
        #expect(throws: KokoroRuntimeDecision.Invalid.cacheLimit) { try Self.decision(gpuCacheLimitBytes: 0) }
    }

    @Test func rejectsACacheLimitLargerThanTheWholeFootprint() {
        #expect(throws: KokoroRuntimeDecision.Invalid.cacheLimit) {
            try Self.decision(peakFootprintBytes: 100, gpuCacheLimitBytes: 101)
        }
    }

    @Test func rejectsAModelChecksumThatIsNotTheShippedModel() {
        #expect(throws: KokoroRuntimeDecision.Invalid.checksum) {
            try Self.decision(modelSHA256: String(repeating: "0", count: 64))
        }
    }

    @Test func rejectsAVoicesChecksumThatIsNotTheShippedVoiceTable() {
        #expect(throws: KokoroRuntimeDecision.Invalid.checksum) {
            try Self.decision(voicesSHA256: String(repeating: "0", count: 64))
        }
    }

    @Test(arguments: ["", "   "])
    func rejectsADecisionThatNamesNoFinding(source: String) {
        #expect(throws: KokoroRuntimeDecision.Invalid.source) { try Self.decision(source: source) }
    }

    // MARK: The derived rate cap

    @Test(arguments: [(0.35, 2.0), (0.1, 4.0)])
    func derivesTheRateCapFromTheMeasuredRealTimeFactor(rtf: Double, expected: Double) throws {
        let decision = try Self.decision(measuredRTF: rtf)
        #expect(decision.maxSustainableRate == expected)
        #expect(decision.maxSustainableRate == RateLimits.maxSustainableRate(rtf: rtf))
    }

    @Test func keepsTheFieldsItWasGiven() throws {
        let decision = try Self.decision()
        #expect(decision.runtime == "mlx")
        #expect(decision.packagePins == "kokoro-ios 1.0.11, mlx-swift 0.30.2, MisakiSwift 1.0.6, MLXUtilsLibrary 0.0.6")
        #expect(decision.peakFootprintBytes == 400 * 1024 * 1024)
        #expect(decision.gpuCacheLimitBytes == 96 * 1024 * 1024)
        #expect(decision.isDebugOverride == false)
        #expect(KokoroRuntimeDecision.minimumGPUFamily == .apple7)
    }

    // MARK: The gate

    /// The shipping gate. When the iPhone 17 Pro measurements land in `spikes/findings/`, replace
    /// this with checks on the real values: the RTF, the footprint, the cache limit, the two
    /// permissions and the finding file `current` was transcribed from.
    @Test func thereIsNoShippingDecisionUntilTheDeviceMeasurementsLand() {
        #expect(KokoroRuntimeDecision.current == nil)
    }

    @Test func resolvesToNothingWithoutTheDebugFlag() {
        Self.withIsolatedDefaults { defaults in
            #expect(KokoroRuntimeDecision.resolved(defaults: defaults, environment: [:]) == nil)
        }
    }

    #if DEBUG
    @Test func resolvesToTheLabelledOverrideForTheDefaultsKey() {
        Self.withIsolatedDefaults { defaults in
            defaults.set(true, forKey: KokoroRuntimeDecision.debugOverrideDefaultsKey)
            let resolved = KokoroRuntimeDecision.resolved(defaults: defaults, environment: [:])
            #expect(resolved == KokoroRuntimeDecision.debugOverride)
            #expect(resolved?.isDebugOverride == true)
            #expect(resolved?.source == "DEBUG override — not measured")
        }
    }

    @Test func resolvesToTheLabelledOverrideForTheEnvironmentKey() {
        Self.withIsolatedDefaults { defaults in
            let resolved = KokoroRuntimeDecision.resolved(
                defaults: defaults,
                environment: [KokoroRuntimeDecision.debugOverrideEnvironmentKey: "1"]
            )
            #expect(resolved == KokoroRuntimeDecision.debugOverride)
            #expect(resolved?.isDebugOverride == true)
        }
    }

    /// The override stands in for measurements, so it has to satisfy every rule a real decision does.
    @Test func theLabelledOverrideCarriesTheOwnersPassBar() {
        let override = KokoroRuntimeDecision.debugOverride
        #expect(override.measuredRTF == 0.35)
        #expect(override.maxSustainableRate == 2.0)
        #expect(override.peakFootprintBytes == 400 * 1024 * 1024)
        #expect(override.gpuCacheLimitBytes == 96 * 1024 * 1024)
        #expect(override.backgroundInferencePermitted == false)
        #expect(override.idleInferencePermitted == false)
        #expect(override.modelSHA256 == KokoroResources.modelSHA256)
        #expect(override.voicesSHA256 == KokoroResources.voicesSHA256)
    }
    #endif

    /// Runs `body` against a `UserDefaults` nothing else on this machine writes to, and removes it
    /// afterwards, so a test never leaves a debug flag behind in the standard domain.
    private static func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let name = "KokoroRuntimeDecisionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("could not open an isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
