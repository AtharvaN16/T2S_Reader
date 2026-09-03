import Foundation
import Metal

/// Whether this device, this build and these files can run Kokoro at all (spec §3, plan adjustment 3).
///
/// The question is asked once, at configuration time, and its answer routes a whole document: a
/// document that cannot use Kokoro is planned on `system:` voices from the start, never switched
/// mid-utterance.
public enum KokoroAvailability {
    /// Why the route is closed. Each case's description is what the reader is told.
    public enum Reason: Hashable, Sendable, CustomStringConvertible {
        /// mlx-swift cannot link for the simulator, so the route is closed there by construction.
        case simulator
        case noMetalDevice
        /// §7.3: kokoro-ios needs Apple GPU family 7.
        case gpuFamilyUnsupported
        /// ``KokoroRuntimeDecision/current`` is still nil — the device measurements have not landed.
        case noRuntimeDecision
        case resources(KokoroResources.Failure)

        public var description: String {
            switch self {
            case .simulator: "Not available in the simulator."
            case .noMetalDevice: "This device has no GPU Kokoro can use."
            case .gpuFamilyUnsupported: "Needs an iPhone with an A14 chip or newer (iPhone 12 and later)."
            case .noRuntimeDecision: "Waiting for the device measurements from Plan 0."
            case .resources(let failure): failure.errorDescription ?? "The Kokoro voice data is unusable."
            }
        }
    }

    public enum Verdict: Hashable, Sendable {
        /// Both the numbers and the files: enough to build an engine without asking anything again.
        case available(decision: KokoroRuntimeDecision, resources: KokoroResources.Located)
        case unavailable(Reason)
    }

    /// Every input the probe reads, injectable so the tests can put this machine in any state — the
    /// resource directory included, since `xcodebuild test` forwards no environment of its own to the
    /// test process and `T2S_KOKORO_RESOURCES` would never arrive.
    public struct Probe: Sendable {
        public var isSimulator: Bool
        /// nil when there is no Metal device at all; otherwise whether it reaches
        /// ``KokoroRuntimeDecision/minimumGPUFamily``.
        public var supportsRequiredGPUFamily: @Sendable () -> Bool?
        public var resourcesDirectory: URL?
        public var decision: KokoroRuntimeDecision?

        public init(
            isSimulator: Bool,
            supportsRequiredGPUFamily: @escaping @Sendable () -> Bool?,
            resourcesDirectory: URL?,
            decision: KokoroRuntimeDecision?
        ) {
            self.isSimulator = isSimulator
            self.supportsRequiredGPUFamily = supportsRequiredGPUFamily
            self.resourcesDirectory = resourcesDirectory
            self.decision = decision
        }

        /// The app's own inputs.
        public static func live(
            bundle: Bundle = .main,
            defaults: UserDefaults = .standard,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Probe {
            Probe(
                isSimulator: isSimulatorBuild,
                supportsRequiredGPUFamily: {
                    MTLCreateSystemDefaultDevice()?.supportsFamily(KokoroRuntimeDecision.minimumGPUFamily)
                },
                resourcesDirectory: KokoroResources.bundled(in: bundle),
                decision: KokoroRuntimeDecision.resolved(defaults: defaults, environment: environment)
            )
        }

        #if targetEnvironment(simulator)
        private static let isSimulatorBuild = true
        #else
        private static let isSimulatorBuild = false
        #endif
    }

    /// Cheap checks first and the 340 MB hash last: simulator → Metal device → GPU family → decision
    /// → the files exist at the right size → the files hash to the recorded digests.
    ///
    /// `nonisolated` and `async`: the hashing runs on the caller's task, wherever that is, and in
    /// Swift 6 that is never the main actor — see ``KokoroAvailabilityModel``.
    public static func check(_ probe: Probe) async -> Verdict {
        if probe.isSimulator { return .unavailable(.simulator) }
        guard let supportsRequiredGPUFamily = probe.supportsRequiredGPUFamily() else {
            return .unavailable(.noMetalDevice)
        }
        guard supportsRequiredGPUFamily else { return .unavailable(.gpuFamilyUnsupported) }
        guard let decision = probe.decision else { return .unavailable(.noRuntimeDecision) }
        guard let directory = probe.resourcesDirectory else {
            return .unavailable(.resources(.missing(KokoroResources.modelFileName)))
        }

        let located: KokoroResources.Located
        switch KokoroResources.locate(in: directory) {
        case .success(let success): located = success
        case .failure(let failure): return .unavailable(.resources(failure))
        }
        do {
            try KokoroResources.verify(located)
        } catch let failure as KokoroResources.Failure {
            return .unavailable(.resources(failure))
        } catch {
            // A file that exists at the right size but cannot be read through: unprovable, so it is
            // treated exactly like a file whose contents are wrong.
            return .unavailable(.resources(.checksumMismatch(KokoroResources.modelFileName)))
        }
        return .available(decision: decision, resources: located)
    }
}
