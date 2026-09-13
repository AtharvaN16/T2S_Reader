import Foundation

/// How many utterances in a row the voice has failed to speak.
///
/// Spec §6 fills a failed utterance with 200 ms of silence and carries on, so a single failure is a
/// hiccup the reader loses one sentence to and never needs told about — it is logged and nothing
/// more. A run of them is a different thing: the voice is not working, which is worth saying once,
/// plainly, and with nothing to tap because there is nothing the reader can do.
///
/// The counting has one trap in it. A failure is *followed* by a `.rendered` carrying that
/// utterance's silence (`RenderScheduler`), so treating every `.rendered` as a recovery would reset
/// the run on every failure and the threshold could never be reached. A render only counts as a
/// recovery when it is for some other utterance.
struct RenderFailureRun {
    /// Five, on the owner's word (2026-09-13). Low enough to catch a voice whose assets never
    /// downloaded within a few sentences, high enough that a bad patch of one book does not accuse
    /// the app of being broken.
    static let threshold = 5

    private(set) var count = 0
    private var lastFailed: Int?

    var isPersistent: Bool { count >= Self.threshold }

    mutating func failed(utterance: Int) {
        count += 1
        lastFailed = utterance
    }

    mutating func rendered(utterance: Int) {
        guard utterance != lastFailed else { return }               // the silence for a failure
        reset()
    }

    mutating func reset() {
        count = 0
        lastFailed = nil
    }
}
