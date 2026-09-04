import Foundation
import T2SCore

/// The Plan 0 Task 8 Core ML spike findings (spec §7.3, §7.5) written down as constants, so the app
/// never takes the Core ML Kokoro route on a guess.
///
/// Smaller than ``KokoroRuntimeDecision``: the Core ML arm runs CPU-only (no GPU family gate, no GPU
/// cache limit) and the spike that measured it did not exercise background or idle inference, so this
/// type carries neither permission. Every field is transcribed from
/// `spikes/findings/2026-09-04-pre-a14-runtime.md`; nothing here is estimated.
public struct KokoroCoreMLDecision: Hashable, Sendable {
    /// The model files these numbers were measured with; ``KokoroCoreMLResources/modelRevision``.
    public let modelRevision: String
    /// The inference runtime, "coreml-cpu".
    public let runtime: String
    /// §7.3: the median real-time factor, rendering flat out, on the slowest device measured (an A13).
    public let measuredRTF: Double
    /// The highest playback rate that measurement sustains. Derived from ``measuredRTF``, never
    /// passed in, so the rate cap and the RTF can never disagree.
    public let maxSustainableRate: Double
    /// §7.5: peak memory footprint of a render, in bytes.
    public let peakFootprintBytes: Int
    /// The finding file these numbers were transcribed from, e.g.
    /// "spikes/findings/2026-09-04-pre-a14-runtime.md".
    public let source: String

    /// Why a set of numbers is not a decision. No payload: each case names one rule.
    public enum Invalid: Error, Equatable, Sendable {
        case rtf
        case footprint
    }

    public init(modelRevision: String, runtime: String, measuredRTF: Double, peakFootprintBytes: Int, source: String) throws {
        guard measuredRTF.isFinite, measuredRTF > 0 else { throw Invalid.rtf }
        guard peakFootprintBytes > 0 else { throw Invalid.footprint }

        self.modelRevision = modelRevision
        self.runtime = runtime
        self.measuredRTF = measuredRTF
        self.maxSustainableRate = RateLimits.maxSustainableRate(rtf: measuredRTF)
        self.peakFootprintBytes = peakFootprintBytes
        self.source = source
    }

    /// The measured decision: RTF 0.181 and a 119 MiB footprint on an A13
    /// (`spikes/findings/2026-09-04-pre-a14-runtime.md`), CPU-only.
    public static let current: KokoroCoreMLDecision = {
        do {
            return try KokoroCoreMLDecision(
                modelRevision: KokoroCoreMLResources.modelRevision,
                runtime: "coreml-cpu",
                measuredRTF: 0.181,
                peakFootprintBytes: 119 * 1024 * 1024,
                source: "spikes/findings/2026-09-04-pre-a14-runtime.md"
            )
        } catch {
            preconditionFailure("the measured Core ML decision is not valid: \(error)")
        }
    }()
}
