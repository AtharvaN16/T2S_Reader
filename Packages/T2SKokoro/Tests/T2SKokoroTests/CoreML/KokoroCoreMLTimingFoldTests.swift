import Foundation
import Testing
@testable import T2SKokoro

/// The fold is pure arithmetic over synthetic frames: no model, no G2P, microseconds per test.
@Suite struct KokoroCoreMLTimingFoldTests {
    /// 600 samples at 24 kHz.
    static let frame = 0.025

    static func token(_ text: String, _ whitespace: String = "") -> KokoroToken {
        KokoroToken(text: text, whitespace: whitespace, start: nil, end: nil)
    }

    /// One word owning two ids. `frames` is `[BOS, id0, id1, EOS]`, so the word starts after the
    /// BOS frame and ends after its own two.
    @Test func timesOneWordFromTheFramesItOwns() {
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi")],
            pieces: [.init(owners: [0, 0], frames: [2, 4, 6, 1], offsetSeconds: 0)]
        )
        #expect(tokens.count == 1)
        #expect(tokens[0].start == 2 * Self.frame)
        #expect(tokens[0].end == 12 * Self.frame)
    }

    /// The pause between two words is a whitespace id, which belongs to no word: the first word ends
    /// where its last phoneme does, and the second starts after the pause. This is the §7.4
    /// trailing-pause fix (`spikes/findings/2026-09-04-pre-a14-runtime.md`), which is why the word
    /// ends are not simply the next word's starts.
    @Test func chargesTheGapBetweenTwoWordsToNeitherOfThem() {
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi", " "), Self.token("there")],
            pieces: [.init(owners: [0, KokoroCoreMLTimingFold.noOwner, 1], frames: [0, 4, 8, 4, 0], offsetSeconds: 0)]
        )
        #expect(tokens[0].start == 0 && tokens[0].end == 4 * Self.frame)
        #expect(tokens[1].start == 12 * Self.frame && tokens[1].end == 16 * Self.frame)
    }

    /// A full stop owns the breath after the sentence — that is where the pause went — but it is not
    /// a word, and a timing for it would highlight the punctuation.
    @Test func leavesAPunctuationOnlyTokenUntimed() {
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi"), Self.token(".")],
            pieces: [.init(owners: [0, 1], frames: [0, 4, 20, 0], offsetSeconds: 0)]
        )
        #expect(tokens[0].end == 4 * Self.frame)
        #expect(tokens[1].start == nil && tokens[1].end == nil)
    }

    /// A word whose phonemes were all dropped by the tokenizer owns no id, so it is left untimed and
    /// the mapper skips it rather than guessing.
    @Test func leavesATokenThatOwnsNoIdsUntimed() {
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi"), Self.token("shrug")],
            pieces: [.init(owners: [0], frames: [0, 4], offsetSeconds: 0)]
        )
        #expect(tokens[1].start == nil && tokens[1].end == nil)
    }

    /// A long utterance is synthesized in consecutive pieces, and each piece's timings are offset by
    /// the audio the pieces before it produced.
    @Test func offsetsALaterPieceByTheAudioBeforeIt() {
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi", " "), Self.token("there")],
            pieces: [
                .init(owners: [0], frames: [0, 4], offsetSeconds: 0),
                .init(owners: [1], frames: [0, 8], offsetSeconds: 1.5),
            ]
        )
        #expect(tokens[0].start == 0 && tokens[0].end == 4 * Self.frame)
        #expect(tokens[1].start == 1.5 && tokens[1].end == 1.5 + 8 * Self.frame)
    }

    @Test func leavesEveryTokenUntimedForNoPieces() {
        let tokens = KokoroCoreMLTimingFold.timedTokens([Self.token("Hi")], pieces: [])
        #expect(tokens == [Self.token("Hi")])
    }
}
