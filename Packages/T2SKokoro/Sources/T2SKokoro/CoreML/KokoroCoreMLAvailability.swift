import Foundation
import Observation

/// Whether this build's files can run Kokoro on Core ML (spec §3, §6).
///
/// Asked once, at configuration time, and its answer routes a whole document, exactly like
/// ``KokoroAvailability``. Much shorter than the MLX probe, and deliberately: the Core ML route runs
/// CPU-only on every device the app supports and in the simulator, and ``KokoroCoreMLDecision/current``
/// is a constant rather than something that may be missing — so the only question left is whether the
/// model files were staged.
public enum KokoroCoreMLAvailability {
    /// Why the route is closed. The description is what the reader is told.
    public enum Reason: Hashable, Sendable, CustomStringConvertible {
        /// Neither the bundle nor the install directory has a complete model: the app downloads it
        /// (`KokoroCoreMLInstall`). The payload is what the install directory was missing.
        case notInstalled(KokoroCoreMLResources.Failure)
        /// A bundle that stages the model has it incomplete — a developer's build, never a
        /// download's, which `notInstalled` covers.
        case resources(KokoroCoreMLResources.Failure)

        public var description: String {
            switch self {
            case .notInstalled: "The Kokoro voice is not downloaded yet."
            case .resources(let failure): failure.errorDescription ?? "The Core ML Kokoro model is unusable."
            }
        }
    }

    public enum Verdict: Hashable, Sendable {
        /// Both the numbers and the files: enough to build an engine without asking anything again.
        case available(decision: KokoroCoreMLDecision, resources: KokoroCoreMLResources.Located)
        case unavailable(Reason)
    }

    /// Presence only, and therefore synchronous: every file was checked against its digest when it
    /// was staged or downloaded, so there is nothing here worth hashing hundreds of megabytes for at
    /// launch — unlike ``KokoroAvailability/check(_:)``, whose weights arrive as one opaque archive.
    ///
    /// The bundle first — a developer's build may still stage the model — then the install
    /// directory (`KokoroCoreMLInstall.defaultRoot`), else ``Reason/notInstalled`` with what the
    /// install directory lacked, which is what a fresh install reports.
    public static func check(bundle: Bundle, installRoot: URL? = nil) -> Verdict {
        if case .success(let located) = KokoroCoreMLResources.locate(in: bundle) {
            return .available(decision: .current, resources: located)
        }
        guard let installRoot else { return verdict(for: KokoroCoreMLResources.locate(in: bundle)) }
        switch KokoroCoreMLResources.locate(installedIn: installRoot) {
        case .success(let located): return .available(decision: .current, resources: located)
        case .failure(let failure): return .unavailable(.notInstalled(failure))
        }
    }

    /// The same question asked of the development layout `scripts/fetch-kokoro-coreml.sh --app`
    /// stages, which is the only form the package's own tests can see.
    static func check(directory: URL) -> Verdict {
        verdict(for: KokoroCoreMLResources.locate(inDirectory: directory))
    }

    private static func verdict(for located: Result<KokoroCoreMLResources.Located, KokoroCoreMLResources.Failure>) -> Verdict {
        switch located {
        case .success(let resources): .available(decision: .current, resources: resources)
        case .failure(let failure): .unavailable(.resources(failure))
        }
    }
}

/// One Core ML availability answer per launch, shared by the composition root, the voice list and the
/// voice-route fallback — the ``KokoroAvailabilityModel`` of the Core ML route.
///
/// It has no `resolve()` and starts no task: the verdict costs a handful of `fileExists` calls, so
/// `init` answers the question outright and `state` is never observed as `.checking`. The case is
/// kept so this model, the MLX one and the app's Kokoro status enum all read the same way.
@MainActor
@Observable
public final class KokoroCoreMLAvailabilityModel {
    public enum State: Hashable, Sendable {
        /// Never reached by this model; see the type's note.
        case checking
        case available(KokoroCoreMLDecision)
        /// ``KokoroCoreMLAvailability/Reason/description``. A resource failure names the fetch
        /// script, so the app still decides what of it a reader should see.
        case unavailable(String)
    }

    public private(set) var state: State
    /// The whole answer, files included, for the composition root that goes on to build an engine.
    /// Decided in `init`; an install that completes later moves it to available (`installed(_:)`).
    public private(set) var verdict: KokoroCoreMLAvailability.Verdict

    private let bundle: Bundle
    private let installRoot: URL?

    public init(bundle: Bundle = .main, installRoot: URL? = nil) {
        self.bundle = bundle
        self.installRoot = installRoot
        let verdict = KokoroCoreMLAvailability.check(bundle: bundle, installRoot: installRoot)
        self.verdict = verdict
        switch verdict {
        case .available(let decision, _): state = .available(decision)
        case .unavailable(let reason): state = .unavailable(reason.description)
        }
    }

    /// Whether the model must be downloaded before the route can open.
    public var needsInstall: Bool {
        if case .unavailable(.notInstalled) = verdict { return true }
        return false
    }

    /// The installer finished: the route's files are `resources` from here on.
    public func installed(_ resources: KokoroCoreMLResources.Located) {
        verdict = .available(decision: .current, resources: resources)
        state = .available(.current)
    }

    /// Asks the files again, for the one thing that can take them away mid-session: the reader
    /// deleting the model in Settings → Storage. The verdict is otherwise decided once, in `init`,
    /// and only ever moves forward through ``installed(_:)``.
    public func recheck() {
        verdict = KokoroCoreMLAvailability.check(bundle: bundle, installRoot: installRoot)
        switch verdict {
        case .available(let decision, _): state = .available(decision)
        case .unavailable(let reason): state = .unavailable(reason.description)
        }
    }
}
