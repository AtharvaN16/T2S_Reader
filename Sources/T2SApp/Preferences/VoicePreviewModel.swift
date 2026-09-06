import Foundation
import Observation
import T2SAudio
import T2SCore

/// Renders and plays one sample sentence for whichever voice a picker row previews. Every group
/// previews the same way — Kokoro, system and cloud alike — because the voice ID already tells
/// `RoutedEngine` (or a fake, in tests) which engine to ask; this model needs no branching per group.
@MainActor
@Observable
public final class VoicePreviewModel {
    /// Read aloud by every preview. Plain prose, not a pangram: a reader is judging tone and
    /// clarity, not phoneme coverage.
    public static let sampleText = "It was a bright, cold morning, and the whole town seemed to be holding its breath."

    /// The voice ID currently rendering or playing, or nil when nothing is previewing.
    public private(set) var previewing: String?
    /// True from the moment a preview starts until its synthesis has returned, one way or another.
    public private(set) var isRendering = false
    public private(set) var lastError: String?

    private let engine: any SynthesisEngine
    private let makePlayer: @MainActor (Double) -> any AudioPlaying
    /// The app's hook to pause book playback before a preview speaks, so the two are never heard
    /// at once.
    private let beforePreview: @MainActor () async -> Void
    private var task: Task<Void, Never>?
    private var player: (any AudioPlaying)?

    public init(engine: any SynthesisEngine, makePlayer: @escaping @MainActor (Double) -> any AudioPlaying,
                beforePreview: @escaping @MainActor () async -> Void) {
        self.engine = engine
        self.makePlayer = makePlayer
        self.beforePreview = beforePreview
    }

    /// The same ID toggles it off; any other ID stops whatever was previewing and starts this one.
    public func toggle(_ voiceID: String) {
        if previewing == voiceID {
            stop()
            return
        }
        stop()
        // A failure belongs to the preview that failed, not to the next one.
        lastError = nil
        previewing = voiceID
        isRendering = true
        task = Task { [weak self] in
            await self?.render(voiceID)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        player?.reset()
        player = nil
        previewing = nil
        isRendering = false
    }

    private func render(_ voiceID: String) async {
        await beforePreview()
        // Stopped while the book was being paused: do not pay for a synthesis nobody will hear.
        guard !Task.isCancelled, previewing == voiceID else { return }
        let outcome: Result<SynthesisResult, Error>
        do {
            outcome = .success(try await engine.synthesize(SynthesisRequest(spoken: Self.sampleText, voiceID: voiceID)))
        } catch {
            outcome = .failure(error)
        }
        // Cancelled by `stop()`, or superseded by another `toggle()` while this was in flight:
        // either way, this render's audio is not the one to play.
        guard !Task.isCancelled, previewing == voiceID else { return }
        isRendering = false
        switch outcome {
        case .success(let result):
            let player = makePlayer(result.audio.sampleRate)
            player.onSegmentFinished = { [weak self] _ in
                guard let self, self.previewing == voiceID else { return }
                self.previewing = nil
            }
            self.player = player
            player.enqueue(result.audio, tag: 0)
            player.play()
        case .failure(let error):
            lastError = error.localizedDescription
            previewing = nil
        }
    }
}
