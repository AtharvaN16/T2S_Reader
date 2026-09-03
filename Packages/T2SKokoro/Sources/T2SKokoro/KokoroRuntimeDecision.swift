import Foundation
import Metal
import T2SCore

/// The Plan 0 device findings (spec §7.2–§7.5, §7.7) written down as constants, so the app never
/// takes the Kokoro route on a guess.
///
/// Nothing here is estimated: every field is transcribed from a file under `spikes/findings/`, and
/// ``current`` stays nil until the iPhone 17 Pro measurements are recorded there. The one exception
/// is ``debugOverride``, which exists so the route can be exercised during development and says so
/// in both its ``source`` and ``isDebugOverride``.
public struct KokoroRuntimeDecision: Hashable, Sendable {
    /// The weights the numbers below were measured with; must equal ``KokoroResources/modelSHA256``.
    public let modelSHA256: String
    /// The voice table the numbers below were measured with; must equal ``KokoroResources/voicesSHA256``.
    public let voicesSHA256: String
    /// The inference runtime, "mlx".
    public let runtime: String
    /// The exact package versions the measurement ran against.
    public let packagePins: String
    /// §7.3: the median real-time factor, rendering flat out, on the slowest device we support.
    public let measuredRTF: Double
    /// The highest playback rate that measurement sustains. Derived from ``measuredRTF``, never
    /// passed in, so the rate cap and the RTF can never disagree.
    public let maxSustainableRate: Double
    /// §7.5: peak memory footprint of a render, in bytes.
    public let peakFootprintBytes: Int
    /// The cap put on MLX's GPU buffer cache, chosen from the §7.5 footprint. The cache grows to
    /// whatever the device allows unless it is capped, which is what puts a long render over a
    /// phone's jetsam limit.
    public let gpuCacheLimitBytes: Int
    /// §7.2: whether rendering may continue while the app is in the background.
    public let backgroundInferencePermitted: Bool
    /// §7.7: whether rendering may continue while the device is idle and unplugged.
    public let idleInferencePermitted: Bool
    /// The finding file these numbers were transcribed from, e.g.
    /// "spikes/findings/2026-09-03-runtime-benchmark.md".
    public let source: String
    /// True only for ``debugOverride``. Anything user-visible that depends on these numbers can say
    /// so instead of presenting a development stand-in as a measurement.
    public let isDebugOverride: Bool

    /// §7.3 on the iPhone 11 Pro: kokoro-ios cannot run below Apple GPU family 7 — an A14, i.e. an
    /// iPhone 12 or newer (`spikes/findings/2026-09-03-runtime-benchmark.md`).
    public static let minimumGPUFamily: MTLGPUFamily = .apple7

    /// Why a set of numbers is not a decision. No payload: each case names one rule, and the rules
    /// are checked in the order they are listed here.
    public enum Invalid: Error, Equatable, Sendable {
        case rtf
        case footprint
        case cacheLimit
        case checksum
        case source
    }

    public init(
        modelSHA256: String,
        voicesSHA256: String,
        runtime: String,
        packagePins: String,
        measuredRTF: Double,
        peakFootprintBytes: Int,
        gpuCacheLimitBytes: Int,
        backgroundInferencePermitted: Bool,
        idleInferencePermitted: Bool,
        source: String,
        isDebugOverride: Bool
    ) throws {
        guard measuredRTF.isFinite, measuredRTF > 0 else { throw Invalid.rtf }
        guard peakFootprintBytes > 0 else { throw Invalid.footprint }
        guard gpuCacheLimitBytes > 0, gpuCacheLimitBytes <= peakFootprintBytes else { throw Invalid.cacheLimit }
        guard modelSHA256 == KokoroResources.modelSHA256,
              voicesSHA256 == KokoroResources.voicesSHA256 else { throw Invalid.checksum }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Invalid.source }

        self.modelSHA256 = modelSHA256
        self.voicesSHA256 = voicesSHA256
        self.runtime = runtime
        self.packagePins = packagePins
        self.measuredRTF = measuredRTF
        self.maxSustainableRate = RateLimits.maxSustainableRate(rtf: measuredRTF)
        self.peakFootprintBytes = peakFootprintBytes
        self.gpuCacheLimitBytes = gpuCacheLimitBytes
        self.backgroundInferencePermitted = backgroundInferencePermitted
        self.idleInferencePermitted = idleInferencePermitted
        self.source = source
        self.isDebugOverride = isDebugOverride
    }

    /// The shipping decision, and the gate on the whole route: nil until the iPhone 17 Pro findings
    /// exist (the protocol is in `spikes/README.md`). A release build cannot take the Kokoro route
    /// while this is nil, because ``resolved(defaults:environment:)`` has nothing else to return.
    public static let current: KokoroRuntimeDecision? = nil

    /// What the app should use: the shipping decision, else — in DEBUG builds only, and only when the
    /// defaults key or the environment variable is set — the labelled override. A release build never
    /// sees the override, whatever the flags say.
    public static func resolved(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KokoroRuntimeDecision? {
        if let current { return current }
        #if DEBUG
        if defaults.bool(forKey: debugOverrideDefaultsKey) || isSet(environment[debugOverrideEnvironmentKey]) {
            return debugOverride
        }
        #endif
        return nil
    }

    public static let debugOverrideDefaultsKey = "kokoro.debugOverride"
    public static let debugOverrideEnvironmentKey = "T2S_KOKORO_DEBUG_OVERRIDE"

    #if DEBUG
    /// A development-only stand-in, so the route can be exercised on an A14+ phone before the numbers
    /// land. Its values are the pass bar the owner set — RTF ≤ 0.35, ≤ 400 MB — and *not*
    /// measurements of anything, which is what ``isDebugOverride`` and ``source`` record. The two
    /// permissions are false because neither §7.2 nor §7.7 has been run.
    public static let debugOverride: KokoroRuntimeDecision = {
        do {
            return try KokoroRuntimeDecision(
                modelSHA256: KokoroResources.modelSHA256,
                voicesSHA256: KokoroResources.voicesSHA256,
                runtime: "mlx",
                packagePins: "kokoro-ios 1.0.11, mlx-swift 0.30.2, MisakiSwift 1.0.6, MLXUtilsLibrary 0.0.6",
                measuredRTF: 0.35,
                peakFootprintBytes: 400 * 1024 * 1024,
                gpuCacheLimitBytes: 96 * 1024 * 1024,
                backgroundInferencePermitted: false,
                idleInferencePermitted: false,
                source: "DEBUG override — not measured",
                isDebugOverride: true
            )
        } catch {
            preconditionFailure("the DEBUG override is not a valid decision: \(error)")
        }
    }()

    /// The flag values a developer would type. Anything else — including an unset variable, "0" and
    /// the empty string — leaves the route closed.
    private static func isSet(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes"].contains(value.lowercased())
    }
    #endif
}
