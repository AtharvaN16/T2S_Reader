# Plan 11 — Voice quality, second listen: the tail click and the hyphen pause

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

_2026-09-08. Branch `plan-11-voice-quality-2` off `dev` @ 93811aa, in the worktree
`.worktrees/plan-11-voice-quality-2`. Written from the owner's second listen on the iPhone 11 Pro._

**Goal:** Remove the two faults the owner heard — a tick before a sentence resumes, and a pause inside
every hyphenated compound — and leave the seam between two pipeline calls no longer than the model's own
pauses.

**Architecture:** Both faults are ours, measured in
[spikes/findings/2026-09-08-ticks-and-hyphens.md](../../../spikes/findings/2026-09-08-ticks-and-hyphens.md).
The tick is a 20 ms burst the Core ML pipeline leaves 60–40 ms before the end of every call, bounded by
digital silence; the engine zeroes exactly that shape after each call (`KokoroCoreMLTailClick`). The
hyphen pause is MisakiSwift mapping every `NLTagger` `.dash` token to Kokoro's `—`; the normalizer
turns an intra-word hyphen into a space before the G2P sees it (`SplitHyphenatedCompoundsRule`,
`Versions.normalizer` 3). The seam's dead air after a bare-word cut is trimmed in the engine's join
(`KokoroCoreMLLeadIn`), with the timing fold offset by what was dropped.

**Tech Stack:** Swift 6.2, swift-testing; `swift test` for the root package; `scripts/test-kokoro.sh`
(xcodebuild, macOS) for `Packages/T2SKokoro`; `scripts/quality-probe.sh` renders the evidence.

**Spec:** [docs/superpowers/specs/2026-09-01-t2s-reader-design.md](../specs/2026-09-01-t2s-reader-design.md)
§4.1 (normalizer rules), §3 (engine); the finding above is the measurement the plan argues from.

## Global Constraints

- Never play audio on the owner's Mac; the probe writes WAVs, nothing plays them.
- `Versions.normalizer` / `Versions.segmenter` change only when the spoken text or its segmentation
  changes; a bump re-derives every stored timeline on its next play and orphans rendered audio.
- The engine's word timings must stay within ±100 ms of the audio (spec §7.4); any trim of a piece's
  audio must be folded into `KokoroCoreMLTimingFold.Piece.offsetSeconds`.
- `KokoroCoreMLEngine.Options`'s initializer defaults stay upstream's; the app's choices live in
  `Options.default`.

---

## Tasks

| # | Task | Owns | Verification | State |
|---|---|---|---|---|
| 1 | **Hyphenated compounds are spoken as words.** `SplitHyphenatedCompoundsRule` after `CollapseURLsRule`; `Versions.normalizer` → 3; dictionary terms match the spoken form. | `Sources/T2SCore/Normalize`, `Sources/T2SCore/Versions.swift`, tests | `swift test` (361 tests) | done, c79f00d |
| 2 | **The tail click is removed.** `KokoroCoreMLTailClick.removed(from:)` on every pipeline call's audio, behind `Options.removeTailClick` (`.default` true); the utterance trace and `KokoroQualityProbe` that measured it; the finding. | `Packages/T2SKokoro/Sources/T2SKokoro/CoreML`, its tests, `scripts/quality-probe.sh`, `spikes/findings` | `scripts/test-kokoro.sh`; the probe's tail table shows no island | done pending the probe re-run |
| 3 | **A seam holds a beat, not a hole.** The silence across every seam — the previous piece's end-of-input tail plus the next piece's lead-in — is trimmed to a budget by the kind of cut (word 60 ms, clause 320 ms, sentence 500 ms), the head never past the next piece's BOS frames (the fold offset moves back by what was dropped), the tail as far as the silence goes (the fold clamps the previous piece's last word to the audio that is left). | `KokoroCoreMLEngine.swift`, `KokoroCoreMLTimingFold.swift`, new `KokoroCoreMLSeam.swift`, tests | `scripts/test-kokoro.sh`; the probe's seam lines | done: 740 → 60 ms, 820 → 320 ms, 400 → 310 ms |
| 4 | **Docs.** HANDOFF resume section, README (the probe script), spec §4.1 rule list and changelog. | `docs/`, `README.md` | review | done |

## Decisions taken without the owner (each with its cost if wrong)

- **A space, not a joined word, for the hyphen.** The Python reference concatenates the pieces'
  phonemes; a space lets every piece hit MisakiSwift's lexicon and keeps one word timing per piece for
  the highlighter. Cost: "re-enter" reads as two words, which is how it is said anyway.
- **Digit–digit hyphens keep the dash.** "1990-1995" and "555-1234" read better with the beat than as
  one run. Cost: none audible; a constant if wrong.
- **Fix the click in the engine, not by zeroing punctuation spans (upstream's way).** Span zeroing cut
  speech (Plan 9's measurement); the island rule cannot touch speech. Cost: if a phone's fp16 stages
  leave a floor above −80 dBFS the rule does nothing — the probe on the phone would show it.
- **Seams are trimmed on both sides, to a budget by cut kind.** With the click gone the probe measured
  740 ms across a bare-word cut and 400–820 ms across comma cuts: every call ends with the model's
  end-of-input pause, whatever the cut. Budgets are the model's own pauses inside one call — 25–75 ms
  between words, 320–420 ms at a comma, 230–740 ms at a full stop. The head is trimmed first (BOS
  lead-in is pure silence) and the fold offset moves back with it, so no word start moves. The tail
  is silence the model rendered inside the last word's own frames once the cut made it utterance-final
  (a bare-word cut measured 460 ms of it against 150 ms of pause frames), so the trim takes it and the
  fold clamps that word's end to the audio left. Cost: three constants if the phone listen disagrees.

## Deferred

- **The 30 s Core ML bucket and the 512-token duration model**, so a whole 300-character utterance is one
  call and no sentence is ever cut: the real remedy for the seam's sentence-final tune. A spike.
- **The mechanism of the burst** (a tensor dump at the trim point against the PyTorch reference; the
  lead-in shortfall of 30–45 ms at every seam suggests the generator's output runs ahead of its frames).
- **Upstream patches**: MisakiSwift should map `.dash` to `—` only for a dash that stands alone;
  kokoro-coreml's tails.

---

### Task 3: A seam holds a beat, not a hole

**Files:**
- Create: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLSeam.swift`
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift` — `Options`, `Piece`, `pieces(ids:owners:words:)`, `splitPiece(groups:at:isFinal:words:)`, the join loop in `synthesize`
- Test: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLSeamTests.swift`, `KokoroCoreMLEngineTests.swift`, `KokoroCoreMLTimingFoldTests.swift`

**Interfaces:**
- Consumes: `KokoroCoreMLTailClick.removed(from:)` (Task 2); `KokoroCoreMLTimingFold.Piece(owners:frames:offsetSeconds:)` and `KokoroCoreMLTimingFold.noOwner`; `KokoroVocabulary.sentenceFinalPunctuationTokenIds`, `.clauseBoundaryPunctuationTokenIds`, `.silentPunctuationTokenIds`; `PipelineConstants.sampleRate`, `.samplesPerDurationFrame`.
- Produces: `KokoroCoreMLSeam.Cut` (`.none`, `.word`, `.clause`, `.sentence`); `KokoroCoreMLSeam.budgetSamples(for:)`; `KokoroCoreMLSeam.trimmed(previous:next:budget:tailCap:headCap:) -> (previous: [Float], next: [Float], droppedTail: Int, droppedHead: Int)`; `Piece.cut: KokoroCoreMLSeam.Cut`; `Options.trimSeams: Bool`; `KokoroCoreMLTimingFold.Piece.trimmedTailSeconds: Double`.

- [x] **Step 1: Write the failing tests for the trim**

```swift
// Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLSeamTests.swift
import Foundation
import Testing
@testable import T2SKokoro

/// Every Core ML call ends with the model's end-of-input pause and begins with the BOS lead-in, so
/// the seam between two pieces of one sentence held 400–820 ms of silence (the finding's probe).
/// The trim brings it down to what the model puts at that kind of boundary inside one call.
@Suite struct KokoroCoreMLSeamTests {
    static let rate = 24_000
    static func ms(_ n: Int) -> Int { rate * n / 1000 }
    /// "Speech": a square wave at −10 dBFS, so no sample of it — first or last — ever sits inside the
    /// −50 dBFS silence threshold the way a sine's zero crossings do (a sine fixture failed by one sample).
    static func tone(ms n: Int) -> [Float] {
        (0 ..< ms(n)).map { $0 % 2 == 0 ? 0.3 : -0.3 }
    }
    static func zeros(ms n: Int) -> [Float] { [Float](repeating: 0, count: ms(n)) }

    @Test func dropsFromTheHeadFirst() {
        let previous = Self.tone(ms: 500) + Self.zeros(ms: 100)
        let next = Self.zeros(ms: 300) + Self.tone(ms: 500)
        let t = KokoroCoreMLSeam.trimmed(previous: previous, next: next, budget: Self.ms(300), tailCap: Self.ms(100), headCap: Self.ms(300))
        #expect(t.droppedHead == Self.ms(100))
        #expect(t.droppedTail == 0)
        #expect(t.previous == previous)
        #expect(t.next == Array(next.dropFirst(Self.ms(100))))
    }

    @Test func thenFromTheTailWithinItsCap() {
        let previous = Self.tone(ms: 500) + Self.zeros(ms: 460)
        let next = Self.zeros(ms: 280) + Self.tone(ms: 500)
        let t = KokoroCoreMLSeam.trimmed(previous: previous, next: next, budget: Self.ms(60), tailCap: Self.ms(150), headCap: Self.ms(280))
        #expect(t.droppedHead == Self.ms(280))
        #expect(t.droppedTail == Self.ms(150))
        #expect(t.previous == Array(previous.dropLast(Self.ms(150))))
        #expect(t.next == Array(next.dropFirst(Self.ms(280))))
    }

    @Test func leavesASeamWithinItsBudget() {
        let previous = Self.tone(ms: 500) + Self.zeros(ms: 40)
        let next = Self.zeros(ms: 200) + Self.tone(ms: 500)
        let t = KokoroCoreMLSeam.trimmed(previous: previous, next: next, budget: Self.ms(320), tailCap: Self.ms(40), headCap: Self.ms(200))
        #expect(t.droppedHead == 0 && t.droppedTail == 0)
        #expect(t.previous == previous && t.next == next)
    }

    @Test func treatsTheNoiseFloorAsSilence() {
        let floor = (0 ..< Self.ms(300)).map { Float($0 % 2 == 0 ? 5e-5 : -5e-5) }
        let t = KokoroCoreMLSeam.trimmed(previous: Self.tone(ms: 500), next: floor + Self.tone(ms: 500), budget: Self.ms(60), tailCap: 0, headCap: Self.ms(300))
        #expect(t.droppedHead == Self.ms(240))
    }

    @Test func neverEmptiesEitherSide() {
        let t = KokoroCoreMLSeam.trimmed(previous: Self.zeros(ms: 100), next: Self.zeros(ms: 100), budget: 0, tailCap: Self.ms(100), headCap: Self.ms(100))
        #expect(t.droppedHead == 0 && t.droppedTail == 0)
    }

    @Test func budgetsFollowTheKindOfCut() {
        #expect(KokoroCoreMLSeam.budgetSamples(for: .word) == Self.ms(60))
        #expect(KokoroCoreMLSeam.budgetSamples(for: .clause) == Self.ms(320))
        #expect(KokoroCoreMLSeam.budgetSamples(for: .sentence) == Self.ms(500))
    }
}
```

- [x] **Step 2: Run them to verify they fail**

Run: `cd Packages/T2SKokoro && xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath .build/DerivedData -only-testing:T2SKokoroTests/KokoroCoreMLSeamTests 2>&1 | grep -E "error:|passed|failed"`
Expected: `error: cannot find 'KokoroCoreMLSeam' in scope`

- [x] **Step 3: Write the seam trim**

```swift
// Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLSeam.swift
import Foundation
import KokoroPipeline

/// The silence across the seam between two pieces of one utterance, cut down to what the model puts
/// at that kind of boundary inside a single call.
///
/// Every Core ML call ends with the model's end-of-input pause and begins with the BOS token's
/// lead-in, so a seam measured 400–820 ms of silence whatever the cut — inside a call the model puts
/// 25–75 ms between two words, 320–420 ms at a comma and 230–740 ms at a full stop
/// (`spikes/findings/2026-09-08-ticks-and-hyphens.md`). The head is trimmed first, because the
/// lead-in is pure silence; the tail only as far as the caller's cap, which is the previous piece's
/// trailing pause frames, so no word timing moves.
enum KokoroCoreMLSeam {
    /// How the piece before a seam was closed.
    enum Cut: Sendable, Hashable {
        /// The first piece of an utterance: no seam before it.
        case none
        /// At a bare word, because no punctuation fell in the window before the cap.
        case word
        /// After a comma, semicolon, colon or dash.
        case clause
        /// After a full stop, exclamation or question mark, or an ellipsis.
        case sentence
    }

    /// Below this magnitude a sample is silence: −50 dBFS, the level every pause in the findings is
    /// measured at. The model's decays below it — the tail of a word before a cut, the ramp into the
    /// first word after it — are inaudible and are part of the hole the reader hears.
    static let silence: Float = 0.00316

    /// The silence allowed across a seam, by the cut that made it.
    static func budgetSamples(for cut: Cut) -> Int {
        let rate = PipelineConstants.sampleRate
        switch cut {
        case .none: return .max
        case .word: return rate * 60 / 1000
        case .clause: return rate * 320 / 1000
        case .sentence: return rate * 500 / 1000
        }
    }

    /// `previous` and `next` with the silence across their join cut to at most `budget` samples —
    /// from the head of `next` first (at most `headCap`), then from the tail of `previous` (at most
    /// `tailCap`) — and how much each side lost. Neither side is ever emptied.
    static func trimmed(
        previous: [Float], next: [Float], budget: Int, tailCap: Int, headCap: Int
    ) -> (previous: [Float], next: [Float], droppedTail: Int, droppedHead: Int) {
        var head = 0
        while head < next.count, abs(next[head]) < silence { head += 1 }
        var tail = 0
        while tail < previous.count, abs(previous[previous.count - 1 - tail]) < silence { tail += 1 }
        guard head < next.count, tail < previous.count, budget < .max else { return (previous, next, 0, 0) }
        var excess = head + tail - budget
        guard excess > 0 else { return (previous, next, 0, 0) }
        let droppedHead = min(excess, head, max(0, headCap))
        excess -= droppedHead
        let droppedTail = min(excess, tail, max(0, tailCap))
        return (Array(previous.dropLast(droppedTail)), Array(next.dropFirst(droppedHead)), droppedTail, droppedHead)
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: the Step 2 command. Expected: `Suite KokoroCoreMLSeamTests passed`, 6 tests.

- [x] **Step 5: Write the failing chunker test — a piece knows the cut before it**

Add to `KokoroCoreMLEngineTests`, beside `cutsAtTheLastWordWhenNoPunctuationBoundaryExists`:

```swift
    /// The piece after a cut carries the kind of cut, which is what Task 3's seam budget keys on.
    @Test func recordsTheKindOfCutBeforeEachPiece() throws {
        var words: [MToken] = []
        var ids: [Int32] = []
        var owners: [Int] = []
        Self.appendPlainWords(count: 60, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        let wordCut = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        #expect(wordCut.map(\.cut) == [.none, .word])

        words = []; ids = []; owners = []
        Self.appendPlainWords(count: 20, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        words.append(Self.word(",", phonemes: ","))
        ids += [3, 16]
        owners += [20, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 20, startIndex: 21, words: &words, ids: &ids, owners: &owners)
        let commaCut = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        #expect(commaCut.map(\.cut) == [.none, .clause])

        words = []; ids = []; owners = []
        Self.appendPlainWords(count: 20, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        words.append(Self.word(".", phonemes: "."))
        ids += [4, 16]
        owners += [20, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 20, startIndex: 21, words: &words, ids: &ids, owners: &owners)
        let stopCut = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        #expect(stopCut.map(\.cut) == [.none, .sentence])
    }
```

- [x] **Step 6: Run it to verify it fails**

Run: `... -only-testing:T2SKokoroTests/KokoroCoreMLEngineTests/recordsTheKindOfCutBeforeEachPiece`
Expected: `error: value of type 'KokoroCoreMLEngine.Piece' has no member 'cut'`

- [x] **Step 7: Record the cut on the piece**

In `KokoroCoreMLEngine.swift`, the `Piece` struct gains:

```swift
        /// How the piece before this one was closed — what the seam budget keys on. `.none` for the
        /// first piece of an utterance.
        var cut: KokoroCoreMLSeam.Cut = .none
```

A helper beside `groupEnds(_:with:)`:

```swift
    /// The kind of seam a piece that closes with `group` leaves behind it.
    private static func cut(after group: Group) -> KokoroCoreMLSeam.Cut {
        if groupEnds(group, with: KokoroVocabulary.sentenceFinalPunctuationTokenIds) { return .sentence }
        if groupEnds(group, with: KokoroVocabulary.clauseBoundaryPunctuationTokenIds) { return .clause }
        return .word
    }
```

In `pieces(ids:owners:words:)`, the loop that builds `pieces` from `packed`:

```swift
        for (index, groupSlice) in packed.enumerated() {
            var (piece, lastToken) = Self.piece(
                from: groupSlice[...], firstToken: firstToken, words: words, extendToEnd: index == packed.count - 1
            )
            if index > 0, let previousLast = packed[index - 1].last { piece.cut = Self.cut(after: previousLast) }
            pieces.append(piece)
            firstToken = lastToken + 1
        }
```

In `splitPiece(groups:at:isFinal:words:)`, the second half:

```swift
        var (second, _) = Self.piece(
            from: secondGroups, firstToken: secondGroups.first?.token ?? 0, words: words, extendToEnd: isFinal
        )
        second.cut = Self.cut(after: groups[cutIndex])
        return (first, second)
```

and the first half keeps the cut the whole piece had: add a parameter `inheriting cut: KokoroCoreMLSeam.Cut` to `splitPiece`, pass `piece.cut` from both callers (`renderWithSplitting` and `renderSplittingOnOverflow`), and set `first.cut = cut` after building `first` (make `first` a `var`).

- [x] **Step 8: Run the chunker tests to verify they pass**

Run: `... -only-testing:T2SKokoroTests/KokoroCoreMLEngineTests`. Expected: every chunking and splitting test passes, the new one included.

- [x] **Step 9: Wire the trim into the join**

In `Options`:

```swift
        /// Whether the silence across a seam is trimmed to ``KokoroCoreMLSeam``'s budget for the cut
        /// that made it. The app ships `true`: with the tail click gone, a seam measured 400–820 ms
        /// against the 25–420 ms the model puts at the same boundary inside one call.
        public var trimSeams: Bool
```

`trimSeams: Bool = false` in the initializer, `trimSeams: true` in `.default`. In `synthesize`, the
body of the `for (subPiece, result) in rendered` loop becomes:

```swift
                let cleaned = options.removeTailClick ? KokoroCoreMLTailClick.removed(from: result.audio) : result.audio
                var previous = samples
                var next = cleaned
                var droppedHead = 0
                if options.trimSeams, !samples.isEmpty, subPiece.cut != .none {
                    // The head is never trimmed past the BOS token's own span, so the first word's
                    // fold time (offset + BOS frames) stays at or after the piece's first sample. The
                    // tail is silence the model rendered inside the previous piece's last frames; the
                    // fold clamps that piece's last word to what remains.
                    let bosSamples = (result.tokenDurationFrames.first ?? 0) * PipelineConstants.samplesPerDurationFrame
                    let trimmed = KokoroCoreMLSeam.trimmed(
                        previous: samples, next: cleaned, budget: KokoroCoreMLSeam.budgetSamples(for: subPiece.cut),
                        tailCap: .max, headCap: bosSamples
                    )
                    previous = trimmed.previous
                    next = trimmed.next
                    droppedHead = trimmed.droppedHead
                    if trimmed.droppedTail > 0, !folds.isEmpty {
                        folds[folds.count - 1].trimmedTailSeconds = Double(trimmed.droppedTail) / Double(PipelineConstants.sampleRate)
                    }
                }
                // With a crossfade the join overlaps the last 5 ms of the previous piece, so the
                // piece's audio starts that much earlier than a plain append would put it.
                let joined = options.crossfadePieces && !previous.isEmpty
                    ? PcmJoiner.join(segments: [previous, next], sampleRate: PipelineConstants.sampleRate)
                    : previous + next
                // Where the piece's untrimmed audio would have begun: the fold counts BOS frames from
                // here, and the dropped lead-in was inside them.
                let offsetSamples = joined.count - next.count - droppedHead
                folds.append(KokoroCoreMLTimingFold.Piece(
                    owners: subPiece.owners,
                    frames: result.tokenDurationFrames,
                    offsetSeconds: Double(offsetSamples) / Double(PipelineConstants.sampleRate)
                ))
                if utteranceTrace != nil {
                    tracedPieces.append(UtteranceTrace.Piece(
                        ids: subPiece.ids, owners: subPiece.owners, frames: result.tokenDurationFrames,
                        offsetSamples: offsetSamples, sampleCount: next.count, bucketSeconds: result.bucketSeconds
                    ))
                }
                samples = joined
```

- [x] **Step 10: Write the failing fold test for a trimmed tail, then the clamp**

Add to `KokoroCoreMLTimingFoldTests`:

```swift
    /// A seam may take silence the model rendered inside a piece's last frames; the word that owned
    /// those frames then ends where the audio does, not past it (Plan 11 Task 3).
    @Test func clampsTheLastWordToATrimmedTail() {
        // BOS 0, "Hi" 8 frames (200 ms), EOS 4 frames: 300 ms of audio, 150 ms of it cut at the seam.
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi")],
            pieces: [.init(owners: [0], frames: [0, 8, 4], offsetSeconds: 0, trimmedTailSeconds: 0.15)]
        )
        #expect(tokens[0].start == 0)
        #expect(abs(tokens[0].end! - 0.15) < 1e-9)
    }
```

Run it: `error: extra argument 'trimmedTailSeconds' in call`. Then in `KokoroCoreMLTimingFold.Piece`:

```swift
        /// Seconds cut from the end of this piece's audio at the seam after it (Plan 11 Task 3):
        /// silence the model rendered inside its last frames. No token may end later than the audio
        /// that is left, so the last word's end is clamped to it.
        var trimmedTailSeconds: Double = 0

        init(owners: [Int], frames: [Int], offsetSeconds: Double, trimmedTailSeconds: Double = 0) {
            self.owners = owners
            self.frames = frames
            self.offsetSeconds = offsetSeconds
            self.trimmedTailSeconds = trimmedTailSeconds
        }
```

and in `spans(in:)`, the final `reduce`:

```swift
        // Where the piece's audio ends once the seam after it took its trimmed tail.
        let audioEnd = piece.offsetSeconds + Double(piece.frames.reduce(0, +)) * secondsPerFrame - piece.trimmedTailSeconds
        return first.reduce(into: [:]) { spans, entry in
            let (owner, firstID) = entry
            guard let lastID = last[owner] else { return }
            let end = min(audioEnd, piece.offsetSeconds + Double(cumulative[lastID + 1]) * secondsPerFrame)
            spans[owner] = (min(end, piece.offsetSeconds + Double(cumulative[firstID]) * secondsPerFrame), end)
        }
```

Run the fold tests: all pass.

- [x] **Step 11: Pin the fold contract for a trimmed head**

Add to `KokoroCoreMLTimingFoldTests`:

```swift
    /// A piece whose lead-in was trimmed reports where its untrimmed audio would have begun, so the
    /// BOS frames still land the first word on the sample it actually starts at.
    @Test func aTrimmedLeadInMovesTheOffsetBackNotTheWord() {
        // BOS 12 frames (300 ms); 240 ms of it were dropped, so the audio starts at 1.0 s and the
        // offset is 0.76 s: the word starts at 0.76 + 0.3 = 1.06 s.
        let tokens = KokoroCoreMLTimingFold.timedTokens(
            [Self.token("Hi")],
            pieces: [.init(owners: [0], frames: [12, 4], offsetSeconds: 0.76)]
        )
        #expect(abs(tokens[0].start! - 1.06) < 1e-9)
    }
```

It passes as written: the fold needs no change. It pins the contract the engine now relies on.

- [x] **Step 12: Extend the model-backed seam test**

In `KokoroCoreMLEngineTests.synthesizesALongPassageInPieces`, after the existing expectations:

```swift
        // Seams hold a beat, not a hole: no quiet stretch in the audio longer than the model's own
        // sentence pause. Before Task 3 the two seams measured 740 and 820 ms.
        let window = 240
        var longestQuietMs = 0
        var run = 0
        var i = 0
        while i + window <= result.audio.samples.count {
            let rms = (result.audio.samples[i ..< i + window].reduce(0) { $0 + $1 * $1 } / Float(window)).squareRoot()
            if rms < 0.00316 { run += 1 } else { longestQuietMs = max(longestQuietMs, run * 10); run = 0 }
            i += window
        }
        #expect(longestQuietMs <= 600)
```

- [x] **Step 13: Run the whole Kokoro suite**

Run: `scripts/test-kokoro.sh`. Expected: `** TEST SUCCEEDED **`, the model-backed tests included.

- [x] **Step 14: Re-run the probe and read the seam lines**

Run: `scripts/quality-probe.sh`. In `report.md` section 2, `seam 1` (a word cut) should show `quiet before` + `quiet after` ≤ 60 ms and `seam 2` (a comma cut) ≤ 320 ms; the `gaps` list should no longer hold 740 ms and 820 ms entries at 10.2 s and 20.2 s. Section 3's `packed-1` seam ≤ 320 ms.

- [x] **Step 15: Commit**

```bash
git add Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLSeam.swift Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLSeamTests.swift Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLEngineTests.swift Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLTimingFoldTests.swift
git commit -m "Plan 11 Task 3: a seam holds a beat — the silence across it is trimmed to the model's own pause for the cut, within the trailing pause frames and the BOS lead-in"
```

### Task 4: Docs

**Files:**
- Modify: `docs/HANDOFF.md` (resume section), `README.md` (scripts), `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (§4.1 rule list, §11 changelog)

- [x] **Step 1: HANDOFF** — a "Resume here (2026-09-08) — Plan 11" section: the two findings in one
  paragraph each, what Tasks 1–3 changed, the normalizer-3 upgrade cost, the phone checklist (listen
  for: no tick before a sentence resumes; "commander-in-chief" as one phrase; a two-piece sentence
  flowing through its seam), and the deferred list.
- [x] **Step 2: README** — `scripts/quality-probe.sh` beside `scripts/audio-probe.sh` in the scripts
  list, one line each.
- [x] **Step 3: Spec** — §4.1 list gains "4b. Split hyphenated compounds into words (after URLs, before
  numerals) — MisakiSwift reads a hyphen as a dash"; §11 changelog entry for this plan; the revision
  line at the top.
- [x] **Step 4: Commit** — `git commit -m "Plan 11 Task 4: docs — HANDOFF resume section, README, spec §4.1 rule 4b and changelog"`.
