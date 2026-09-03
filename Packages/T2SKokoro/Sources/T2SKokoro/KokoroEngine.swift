import Dispatch
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary
import T2SAudio
import T2SCore

/// The on-device engine of spec §3: KokoroSwift over MLX, holding one loaded model and the voice
/// table its embeddings come from.
///
/// An actor because the model is mutable state that must be touched one utterance at a time, and
/// because neither `KokoroTTS` nor `MLXArray` is `Sendable` — they never leave this type.
public actor KokoroEngine: SynthesisEngine {
    public static let runtime = "mlx"
    public static let g2p = "misaki1.0.6"

    /// The render-key identity (spec §5): the weights' checksum, the runtime and the G2P version.
    /// Any of the three changing changes the audio, so all three are in the key.
    public static let identity = "kokoro-\(KokoroResources.modelChecksumPrefix)-\(runtime)-\(g2p)"

    public nonisolated let engineID = KokoroEngine.identity

    private let resources: KokoroResources.Located
    private let gpuCacheLimitBytes: Int?
    private var loaded: Loaded?

    /// `generateAudio` blocks its thread for seconds at a time. On the cooperative pool that would
    /// starve every other actor in the app, so this actor runs on a queue of its own instead.
    private let queue = DispatchSerialQueue(label: "com.t2s.reader.kokoro", qos: .userInitiated)
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// The loaded model and voice table, isolated to the actor along with it.
    private struct Loaded {
        let tts: KokoroTTS
        let voices: [String: MLXArray]
    }

    /// `gpuCacheLimitBytes` is ``KokoroRuntimeDecision/gpuCacheLimitBytes``; nil leaves MLX's own
    /// default in place, which is what the tests that do not care about memory use.
    public init(resources: KokoroResources.Located, gpuCacheLimitBytes: Int? = nil) {
        self.resources = resources
        self.gpuCacheLimitBytes = gpuCacheLimitBytes
    }

    /// MLX's buffer-cache cap, as the process currently has it. Internal: the tests assert that
    /// ``init(resources:gpuCacheLimitBytes:)`` actually applied the decision's limit.
    static var currentGPUCacheLimitBytes: Int { Memory.cacheLimit }

    /// Loads the model and the voice table. `synthesize` calls it lazily on first use; a caller that
    /// would rather pay the seconds before playback starts can call it itself.
    public func preload() throws {
        _ = try load()
    }

    @discardableResult
    private func load() throws -> Loaded {
        if let loaded { return loaded }
        // Before anything allocates on the GPU. MLX's buffer cache otherwise grows to whatever the
        // device allows, and on a phone that is what puts a long render over the jetsam limit; the
        // cap comes from the §7.5 footprint in `KokoroRuntimeDecision`.
        if let gpuCacheLimitBytes { Memory.cacheLimit = gpuCacheLimitBytes }
        // The voice table first: it is the far smaller read, and it is the only one of the two that
        // reports failure. `KokoroTTS.init` does not throw on a missing or corrupt model file — it
        // fails later, deep inside MLX — which is why `KokoroResources.verify` has to have run
        // before an engine is constructed at all (the App target does that when it builds the route).
        guard let voices = NpyzReader.read(fileFromPath: resources.voices) else {
            throw KokoroEngineError.voicesUnreadable
        }
        let loaded = Loaded(tts: KokoroTTS(modelPath: resources.model, g2p: .misaki), voices: voices)
        self.loaded = loaded
        return loaded
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        // Both checks come before the load, so a misrouted request costs nothing and the tests that
        // pin them need no model.
        guard let id = KokoroVoiceID(rawValue: request.voiceID), id.engineID == engineID else {
            throw KokoroEngineError.voiceNotForThisEngine(request.voiceID)
        }
        guard !request.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.failed("nothing to speak")
        }
        // The last chance to leave cheaply. The scheduler cancels pending renders on stop, and this
        // actor's queue is serial: without this, a cancelled render would still load a model and
        // synthesize for seconds while the next real one waited behind it.
        try Task.checkCancellation()

        let loaded = try load()
        guard let embedding = loaded.voices["\(id.voice).npy"] else {
            throw KokoroEngineError.unknownVoice(id.voice)
        }
        // The `voices.npz` naming: `a*` are the American voices, `b*` the British ones.
        let language: Language = id.voice.hasPrefix("b") ? .enGB : .enUS

        let samples: [Float]
        let tokens: [MToken]?
        do {
            (samples, tokens) = try loaded.tts.generateAudio(voice: embedding, language: language,
                                                            text: request.spoken, speed: 1.0)
        } catch {
            // The library's own error and never the request text: this string reaches logs.
            throw KokoroEngineError.generation(String(describing: error))
        }

        // The pipeline's PCM is fixed at `PCMAudio.defaultSampleRate`, and `KokoroRuntime.sampleRate`
        // reads KokoroSwift's own constant, so this catches a library or model release that moved the
        // rate instead of silently emitting pitched-up audio. (Comparing the library's constant with
        // `KokoroRuntime.sampleRate` would be a tautology: the latter is derived from the former.)
        guard KokoroRuntime.sampleRate == PCMAudio.defaultSampleRate else {
            throw KokoroEngineError.unexpectedSampleRate(KokoroTTS.Constants.samplingRate)
        }
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw KokoroEngineError.emptyAudio }

        let audio = PCMAudio(sampleRate: KokoroRuntime.sampleRate, samples: samples)
        return SynthesisResult(
            audio: audio,
            wordTimings: KokoroTokenTimingMapper.map((tokens ?? []).map(KokoroToken.init),
                                                     spoken: request.spoken,
                                                     duration: audio.duration)
        )
    }
}

extension KokoroToken {
    /// `MToken` is a mutable class the G2P owns, so the engine copies the four fields the timing
    /// mapper needs into a value that can cross the actor boundary.
    init(_ token: MToken) {
        self.init(text: token.text, whitespace: token.whitespace, start: token.start_ts, end: token.end_ts)
    }
}

public enum KokoroEngineError: Error, Equatable, Sendable, LocalizedError {
    /// The request's voice ID is not a `kokoro:` route for these weights.
    case voiceNotForThisEngine(String)
    case unknownVoice(String)
    case voicesUnreadable
    case unexpectedSampleRate(Int)
    case emptyAudio
    /// KokoroSwift threw. The payload describes the underlying error and never the spoken text.
    case generation(String)

    public var errorDescription: String? {
        switch self {
        case .voiceNotForThisEngine:
            "That voice belongs to a different version of the on-device voice."
        case .unknownVoice(let voice):
            "The on-device voice \"\(voice)\" is not installed."
        case .voicesUnreadable:
            "The Kokoro voice data could not be read. "
                + "Run scripts/fetch-kokoro-model.sh to reinstall it."
        case .unexpectedSampleRate(let rate):
            "The on-device voice produced audio at \(rate) Hz, which this app cannot play."
        case .emptyAudio:
            "The on-device voice produced no audio."
        case .generation:
            "The on-device voice could not speak this passage."
        }
    }
}
