# Plan 15 — Streaming the first sound

_Numbered 14 when it was written; the other session's Plan 14 (the delivery spread) landed first, so this is 15. The branch `plan-14-streaming` and its worktree keep the old number._

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

_2026-09-08. Branch `plan-14-streaming` off `origin/dev` @ 4056ccd (Plan 13 merged on top of Plan 12), in
the worktree `.worktrees/plan-14-streaming`. The owner said "proceed with the next steps"; this is the
audit's #2, the one item that closes the gap to a cloud voice. Other sessions are editing this
repository at the same time (the reading screen, a Kokoro probe): this plan touches none of
`App/T2SReader/Root/`, `Player/`, `Collection/`, `Queue/`, `Reader/`, `Preferences/`._

**Goal:** After a tap on an unrendered position — play, skip, chapter jump, a tapped word, a bookmark —
sound starts when the head utterance's *first piece* has rendered (about a second on an A13 in the
7 s bucket), not when the whole 160-character utterance has (2.5–4.5 s).

**Architecture:** One new path beside the existing one, used only for the utterance the player is
waiting on. `SynthesisEngine` gains `synthesizeStreaming(_:)`, an `AsyncThrowingStream` of
`SynthesisChunk`s — `.piece(audio, ordinal, isLast)` as each piece finishes, then `.finished(wordTimings)`
— with a default that wraps `synthesize` (every engine keeps working; the Kokoro Core ML engine gets a
real implementation with a short first piece). `RenderScheduler` forwards pieces as `.piece` events
while the render runs and stores the concatenation as today. `AudioPlaying.enqueue` gains `isFinal`, so
one utterance can be several buffers with one completion. `PlaybackCoordinator` marks the head request
as streaming when nothing is queued, enqueues pieces as they arrive (starting playback on the first),
and never enqueues past a streaming utterance until its last piece. Everything else — the store, the
timeline, the timings, Prepare — sees exactly what it saw before.

**Tech Stack:** Swift 6.2, swift-testing; `swift test` for the root package; the Kokoro package
compiles only under xcodebuild (see Global Constraints).

**Spec:** [docs/superpowers/specs/2026-09-08-performance-audit.md](../specs/2026-09-08-performance-audit.md)
§3.1 (the design sketch this plan follows), §3.4 (buckets — the 3 s bucket is not staged, so the
first piece lands in the 7 s bucket); the design spec
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](../specs/2026-09-01-t2s-reader-design.md)
§3.3 (two-phase timeline), §3.5 (gapless per-utterance buffers), §3.6 (underrun policy), §7.4 (word
timings within ±100 ms).

## Global Constraints

- **Never play audio on the owner's Mac.** No test in this plan plays anything (`AudioPlayer` tests
  use manual rendering). Never launch the simulator.
- **Other sessions are editing this repository.** Touch only the files each task names. Never run
  `scripts/test-kokoro.sh` (it sweeps Core ML caches other sessions' runs are using). The Kokoro
  package may be *built and its non-model tests run* only when
  `ps aux | grep '[x]codebuild' | grep -c T2SKokoro` prints 0 and `df -h .` shows ≥ 4 GB free, and then
  only as a direct `xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath .build/DerivedData -only-testing:<suite>` from `Packages/T2SKokoro` (no sweep). The
  model files are deliberately absent from this worktree, so every `.enabled(if: KokoroTestSupport.haveCoreMLFiles)`
  test skips itself. If the disk or another session's run blocks the Kokoro build, Task 5 stops and
  reports BLOCKED; the controller decides.
- **Disk is nearly full** (~3 GB free at the time of writing). Before any `swift test`, check
  `df -h .`; below 1.5 GB, stop and report. Never delete anything to make room.
- **The rendered audio in the store is the concatenation of the pieces the player heard.** Word
  timings and `consumedSeconds` are both measured against that concatenation, so the engine's
  streaming join must never alter a piece after it was emitted.
- **The non-streaming path is unchanged**: `synthesize`, the store's contents for a cache key rendered
  either way, `RenderPolicy`, Prepare, the prime, the timeline codec. Only the utterance the player is
  waiting on streams.
- Spec §7.4 still binds the streamed utterance: word onsets within ±100 ms of the audio.
- `KokoroCoreMLEngine.Options`'s initializer defaults stay upstream's.
- Swift 6 language mode, strict concurrency: `SynthesisChunk` is `Sendable`; nothing non-`Sendable`
  crosses an actor hop; the stream's task is cancelled on termination.
- Commit per task from the worktree; messages in the repo's voice ("Plan 14 Task N: what changed — why"),
  ending with a blank line and `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **One utterance, several buffers.** `AudioPlaying.enqueue(_:tag:isFinal:)`; `AudioPlayer` fires one completion per tag; `FakePlayer` and the app's `NullAudioPlaying` follow. | `Sources/T2SAudio/AudioPlaying.swift`, `AudioPlayer.swift`, `Tests/T2SAudioTests/Support/FakePlayer.swift`, `App/T2SReader/AppEnvironment.swift`, `Tests/T2SAudioTests/AudioPlayerTests.swift` | `swift test --filter AudioPlayerTests` |
| 2 | **Engines can stream.** `SynthesisChunk`; `SynthesisEngine.synthesizeStreaming(_:)` with a default; `FakeEngine` streams in pieces under test control; `RoutedEngine` forwards. | `Sources/T2SCore/Render/SynthesisEngine.swift`, `FakeEngine.swift`, `Sources/T2SAudio/RoutedEngine.swift`, tests | `swift test --filter "FakeEngineTests|RoutedEngineTests"` |
| 3 | **The scheduler forwards pieces.** `RenderRequest.stream`; `RenderEvent.piece`; the streaming render path stores the concatenation. | `Sources/T2SCore/Render/RenderScheduler.swift`, `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift` | `swift test --filter RenderSchedulerTests` |
| 4 | **The coordinator plays the first piece.** The head request streams when nothing is queued; pieces are enqueued as they arrive; playback starts on the first; nothing is enqueued past a streaming utterance until its last piece; a stream whose first piece was missed is ignored. | `Sources/T2SAudio/PlaybackCoordinator.swift`, `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift` | `swift test` |
| 5 | **The Kokoro engine streams.** A short first piece; each piece finalized (tail click, seam tail to budget, next head to BOS) before it is emitted; timings folded over the concatenation; `GatedKokoroCoreMLEngine` forwards. | `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift`, `KokoroCoreMLSeam.swift`, their tests, `App/T2SReader/System/GatedKokoroCoreMLEngine.swift` | the Kokoro non-model suites under the constraint above |
| 6 | **Docs.** Spec §3.3/§3.5/§3.6 and rev 15; the audit's progress note (#2); HANDOFF resume section with the phone listen. | `docs/` | review |

## Decisions taken without the owner (each with its cost if wrong)

- **Only the head streams.** Every other utterance in the window renders whole, exactly as before,
  so the cache and Prepare are untouched. Cost: none audible; the head is the only wait a listener
  sees.
- **The first piece is short — 48 ids (≈ 3 s of speech), cut at the best boundary before that.**
  In the 7 s bucket that is ~1 s on an A13. The 3 s bucket would halve it (audit #9), later. Cost: one
  more seam inside the head utterance, trimmed like every other seam.
- **The streaming join is "finalize each piece, then butt them."** A piece's tail silence is cut to
  the seam budget for the cut that follows it (known at cut time), the next piece's lead-in is cut up
  to its BOS frames, no crossfade (the join lands inside silence, so there is nothing to fade). This
  differs slightly from `synthesize`'s join (head first, then tail, 5 ms crossfade); the difference is
  inside a silence under −50 dBFS. Cost: a streamed head is a few milliseconds of silence different
  from the same utterance rendered whole; both are cached under the same key, whichever came first.
- **Pieces carry an ordinal and `isLast`.** The coordinator starts a stream only at ordinal 0 and
  enqueues in order; a stream it joined late (a seek reset the player mid-stream) is ignored and the
  `.rendered` that follows plays from the store as today. Cost: one utterance rendered twice in that
  rare race — no: the store serves it; nothing renders twice.
- **The player's completion fires on the final buffer only**, so `segmentFinished` keeps its meaning.
  Cost: a stream that never gets its last piece (an engine failure mid-utterance) leaves the tag
  without a completion; the scheduler's failure path emits `.rendered` with 200 ms of silence under
  the key, and the coordinator treats that `.rendered` as the end of the stream (see Task 4).

## Deferred

- The 3 s bucket for the first piece (audit #9); the model-backed streaming test on a phone or a Mac
  with ≥ 10 GB free; the seam probe on the streamed join (`scripts/quality-probe.sh`).
- Streaming for every utterance (not only the head) — nothing needs it once the head streams.

---

### Task 1: One utterance, several buffers

**Files:**
- Modify: `Sources/T2SAudio/AudioPlaying.swift`
- Modify: `Sources/T2SAudio/AudioPlayer.swift` (`enqueue`, `manualSegments`)
- Modify: `Tests/T2SAudioTests/Support/FakePlayer.swift`
- Modify: `App/T2SReader/AppEnvironment.swift` (`NullAudioPlaying.enqueue`)
- Test: `Tests/T2SAudioTests/AudioPlayerTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AudioPlaying.enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool)` (protocol requirement);
  `AudioPlaying.enqueue(_:tag:)` (extension, `isFinal: true`); `FakePlayer.enqueuedTags` unchanged
  (one entry per buffer), `FakePlayer.completedTags` unchanged semantics (one completion per tag).

- [ ] **Step 1: Write the failing test**

In `Tests/T2SAudioTests/AudioPlayerTests.swift`, add:

```swift
    /// A streamed utterance is several buffers under one tag; the coordinator's `segmentFinished`
    /// must fire once, after the last of them (spec §3.5: per-utterance completion).
    @Test func severalBuffersUnderOneTagFinishOnce() throws {
        let p = try AudioPlayer(manualRendering: true)
        var finished: [Int] = []
        p.onSegmentFinished = { finished.append($0) }
        p.enqueue(.silence(seconds: 0.4), tag: 7, isFinal: false)
        p.enqueue(.silence(seconds: 0.4), tag: 7, isFinal: false)
        p.enqueue(.silence(seconds: 0.4), tag: 7, isFinal: true)
        p.enqueue(.silence(seconds: 0.2), tag: 8)                    // the two-argument form is final
        p.play()
        try p.renderOffline(seconds: 0.9)
        #expect(finished.isEmpty)                                    // two of three buffers played
        try p.renderOffline(seconds: 0.4)
        #expect(finished == [7])
        #expect(abs(p.consumedSeconds - 1.3) < 0.05)
        try p.renderOffline(seconds: 0.3)
        #expect(finished == [7, 8])
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd .worktrees/plan-14-streaming && swift test --filter AudioPlayerTests 2>&1 | tail -5`
Expected: a compile error, `extra argument 'isFinal' in call`.

- [ ] **Step 3: The protocol**

In `Sources/T2SAudio/AudioPlaying.swift`, replace

```swift
    /// Appends a segment for gapless playback after whatever is queued.
    func enqueue(_ audio: PCMAudio, tag: Int)
```
with
```swift
    /// Appends audio for gapless playback after whatever is queued. A segment — one utterance, one
    /// `tag` — may arrive as several buffers while it streams; `onSegmentFinished` fires once, after
    /// the buffer enqueued with `isFinal`.
    func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool)
```
and after the protocol add:

```swift
public extension AudioPlaying {
    /// A whole segment in one buffer.
    func enqueue(_ audio: PCMAudio, tag: Int) { enqueue(audio, tag: tag, isFinal: true) }
}
```

- [ ] **Step 4: The real player**

In `Sources/T2SAudio/AudioPlayer.swift`, change the signature of `enqueue` to
`public func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool)` and its body so that only a final
buffer produces a completion:

```swift
    public func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        if !audio.samples.isEmpty {
            audio.samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: audio.samples.count)
            }
        }
        scheduledFrames += AVAudioFramePosition(audio.samples.count)
        if manual {
            // Manual mode computes completions from the render clock in `deliverManualCompletions()`
            // rather than observing AVAudioEngine's completion callback — see `manualSegments`'s doc
            // comment. Only a segment's final buffer marks where its completion falls.
            if isFinal { manualSegments.append((tag: tag, endSourceFrames: Double(scheduledFrames))) }
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        } else if isFinal {
            let gen = generation
            // `.dataPlayedBack` fires when the buffer has reached real hardware presentation — the
            // correct "played" signal for real playback, where a functioning run loop / app event
            // cycle services the `Task { @MainActor in ... }` hop below.
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == gen else { return }
                    self.onSegmentFinished?(tag)
                }
            }
        } else {
            // A streamed piece that is not the segment's last: gapless behind the previous buffer,
            // no completion of its own.
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }
```

- [ ] **Step 5: The fakes**

`Tests/T2SAudioTests/Support/FakePlayer.swift`: the queue entries gain `isFinal`, and `advance` fires
the completion only for a final buffer:

```swift
    private(set) var queue: [(tag: Int, remaining: TimeInterval, isFinal: Bool)] = []
    private(set) var enqueuedTags: [Int] = []
    private(set) var resets = 0
    /// Seconds of audio still queued (the head clip's remainder plus every later segment).
    var queuedRemaining: TimeInterval { queue.reduce(0) { $0 + $1.remaining } }

    func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool) {
        queue.append((tag, audio.duration, isFinal))
        enqueuedTags.append(tag)
    }
```
and in `advance(seconds:)`:
```swift
            if queue[0].remaining <= 1e-9 {
                let done = queue.removeFirst()
                if done.isFinal { onSegmentFinished?(done.tag) }
            }
```

`App/T2SReader/AppEnvironment.swift`, `NullAudioPlaying`: `func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool) { if isFinal { queued.append(tag) } }`.

- [ ] **Step 6: Run the player suite, then everything**

Run: `swift test --filter AudioPlayerTests 2>&1 | tail -5` — expected: all pass, the new test included.
Run: `df -h . | tail -1 && swift test 2>&1 | tail -3` — expected: every test passes (383 + 1).
Then, because `AppEnvironment.swift` changed and the app is not built by `swift test`: `grep -n "isFinal" App/T2SReader/AppEnvironment.swift` shows the new signature (the app build is Task 6's, once, if disk allows).

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SAudio/AudioPlaying.swift Sources/T2SAudio/AudioPlayer.swift Tests/T2SAudioTests/Support/FakePlayer.swift App/T2SReader/AppEnvironment.swift Tests/T2SAudioTests/AudioPlayerTests.swift
git commit -m "Plan 14 Task 1: one utterance, several buffers — a segment's completion fires after the buffer marked final, so a streamed head can arrive in pieces"
```

---

### Task 2: Engines can stream

**Files:**
- Modify: `Sources/T2SCore/Render/SynthesisEngine.swift`
- Modify: `Sources/T2SCore/Render/FakeEngine.swift`
- Modify: `Sources/T2SAudio/RoutedEngine.swift`
- Test: `Tests/T2SCoreTests/Render/FakeEngineTests.swift`, `Tests/T2SAudioTests/RoutedEngineTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SynthesisChunk: Sendable {
      case piece(PCMAudio, ordinal: Int, isLast: Bool)
      case finished(wordTimings: [WordTiming])
  }
  protocol SynthesisEngine { … func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> }
  ```
  with a default in an extension (one `.piece(result.audio, ordinal: 0, isLast: true)` then
  `.finished`); `FakeEngine.init(…, pieceCount: Int = 1)` and `FakeEngine.holdBetweenPieces()` /
  `releasePiece()`; `RoutedEngine.synthesizeStreaming` forwards to the routed engine.

- [ ] **Step 1: Write the failing tests**

`Tests/T2SCoreTests/Render/FakeEngineTests.swift` — add:

```swift
    /// The default `synthesizeStreaming` wraps `synthesize`: one piece, then the timings.
    @Test func streamingDefaultIsOnePieceThenFinished() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        var chunks: [SynthesisChunk] = []
        for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: "abcd", voiceID: "v")) { chunks.append(chunk) }
        guard chunks.count == 2, case .piece(let audio, 0, true) = chunks[0], case .finished(let timings) = chunks[1] else {
            Issue.record("expected piece + finished, got \(chunks)"); return
        }
        #expect(abs(audio.duration - 0.4) < 1e-9)
        #expect(timings.count == 1)
    }

    /// A fake that streams in pieces, holding between them so a test can watch the player start
    /// after the first: the pieces concatenate to exactly the whole render.
    @Test func streamsInPiecesThatConcatenateToTheWhole() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 3)
        let whole = try await engine.synthesize(SynthesisRequest(spoken: "abcdefghij", voiceID: "v"))
        var pieces: [PCMAudio] = []
        var finished: [WordTiming]?
        for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: "abcdefghij", voiceID: "v")) {
            switch chunk {
            case .piece(let audio, let ordinal, let isLast):
                #expect(ordinal == pieces.count)
                #expect(isLast == (ordinal == 2))
                pieces.append(audio)
            case .finished(let timings): finished = timings
            }
        }
        #expect(pieces.count == 3)
        #expect(pieces.flatMap(\.samples) == whole.audio.samples)
        #expect(finished == whole.wordTimings)
    }

    @Test func holdBetweenPiecesParksTheStream() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 2)
        await engine.holdBetweenPieces()
        let stream = engine.synthesizeStreaming(SynthesisRequest(spoken: "abcdef", voiceID: "v"))
        var iterator = stream.makeAsyncIterator()
        guard case .piece(_, 0, false)? = try await iterator.next() else { Issue.record("no first piece"); return }
        let second = Task { try await iterator.next() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!second.isCancelled)
        await engine.releasePiece()
        guard case .piece(_, 1, true)? = try await second.value else { Issue.record("no second piece"); return }
    }
```

`Tests/T2SAudioTests/RoutedEngineTests.swift` — add (follow the file's existing fixture for a routed
Kokoro-style engine; if it uses a fake engine keyed by identity, reuse it):

```swift
    /// Streaming is routed like synthesis: the engine that owns the voice answers, in pieces.
    @Test func streamingIsForwardedToTheRoutedEngine() async throws {
        let inner = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 2)
        let routed = RoutedEngine(system: FakeEngine(), kokoro: [], configuration: { nil }, key: { nil })
        // The system route: the `system:` prefix strips to the bare identifier before forwarding.
        var ordinals: [Int] = []
        for try await chunk in routed.synthesizeStreaming(SynthesisRequest(spoken: "abcdef", voiceID: "system:v")) {
            if case .piece(_, let ordinal, _) = chunk { ordinals.append(ordinal) }
        }
        #expect(ordinals == [0])                                     // the system fake streams one piece
        _ = inner
    }
```
(The system engine in the fixture is a plain `FakeEngine`, so one piece is expected; the point is the
call reaches the routed engine's own `synthesizeStreaming`, which `RoutedEngineTests` proves by
observing `requests` on the system fake — add `#expect(await system.requests.map(\.voiceID) == ["v"])`
with the system fake held in a local so the request list is visible.)

- [ ] **Step 2: Run them to see them fail to compile**

Run: `swift test --filter "FakeEngineTests|RoutedEngineTests" 2>&1 | tail -6`
Expected: `cannot find 'SynthesisChunk' in scope`.

- [ ] **Step 3: The protocol and the default**

In `Sources/T2SCore/Render/SynthesisEngine.swift`, after `SynthesisResult`, add:

```swift
/// One step of a streamed render (Plan 14). Pieces arrive in order as the engine finishes them and
/// concatenate to exactly the audio `synthesize` would have returned; `.finished` follows the last
/// piece with the word timings over that concatenation.
public enum SynthesisChunk: Sendable, Hashable {
    case piece(PCMAudio, ordinal: Int, isLast: Bool)
    case finished(wordTimings: [WordTiming])
}
```

Add to the protocol:

```swift
    /// Renders `request` in pieces, yielding each as it completes, then `.finished`. The head
    /// utterance the player is waiting on is rendered this way so the first sound needs one short
    /// piece, not the whole utterance (audit §3.1). Engines that cannot stream yield the whole
    /// render as one piece — the default below.
    func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error>
```

and the default:

```swift
public extension SynthesisEngine {
    func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await synthesize(request)
                    continuation.yield(.piece(result.audio, ordinal: 0, isLast: true))
                    continuation.yield(.finished(wordTimings: result.wordTimings))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: The fake streams**

In `Sources/T2SCore/Render/FakeEngine.swift`: add `public let pieceCount: Int` (init parameter,
default 1), a `private var holdingBetweenPieces = false` with `private var pieceWaiters: [CheckedContinuation<Void, Never>]`,
and:

```swift
    /// Every piece after the first parks until `releasePiece()`, so a test can watch what happens
    /// between the first sound and the rest.
    public func holdBetweenPieces() { holdingBetweenPieces = true }

    public func releasePiece() {
        let waiting = pieceWaiters
        pieceWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    /// The whole render, cut into `pieceCount` near-equal pieces of whole samples — the last takes
    /// the remainder — so the pieces concatenate to exactly `synthesize`'s audio.
    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let whole = try await self.synthesize(request)
                    let count = max(1, await self.pieceCount)
                    let samples = whole.audio.samples
                    let size = samples.count / count
                    for ordinal in 0 ..< count {
                        if ordinal > 0 { await self.waitBetweenPieces() }
                        try Task.checkCancellation()
                        let start = ordinal * size
                        let end = ordinal == count - 1 ? samples.count : start + size
                        continuation.yield(.piece(PCMAudio(sampleRate: whole.audio.sampleRate, samples: Array(samples[start ..< end])),
                                                  ordinal: ordinal, isLast: ordinal == count - 1))
                    }
                    continuation.yield(.finished(wordTimings: whole.wordTimings))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func waitBetweenPieces() async {
        while holdingBetweenPieces { await withCheckedContinuation { pieceWaiters.append($0) } }
    }
```
(`releasePiece()` lets exactly the parked pieces through and leaves `holdingBetweenPieces` set, so
the next piece parks again — a test releases one piece at a time. Add
`public func stopHoldingBetweenPieces() { holdingBetweenPieces = false; releasePiece() }` for tests
that want the rest to flow.)

- [ ] **Step 5: The router forwards**

In `Sources/T2SAudio/RoutedEngine.swift`, add beside `synthesize`:

```swift
    /// Streaming is routed exactly as synthesis is: the engine that owns the voice answers.
    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let routed = try await self.engine(for: request)
                    for try await chunk in routed.engine.synthesizeStreaming(routed.request) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```
and refactor `synthesize` so both share one resolver: `private func engine(for request: SynthesisRequest) async throws -> (engine: any SynthesisEngine, request: SynthesisRequest)` returning the engine and the request to hand it (the Kokoro engine with the request unchanged; the cloud engine with the request unchanged; the system engine with the `system:` prefix stripped; the legacy bare identifier as today). `synthesize` becomes `let routed = try await engine(for: request); return try await routed.engine.synthesize(routed.request)`. The routing decisions and their comments move into the resolver verbatim; behaviour is unchanged (the existing `RoutedEngineTests` prove it).

- [ ] **Step 6: Run the two suites, then everything, and commit**

Run: `swift test --filter "FakeEngineTests|RoutedEngineTests" 2>&1 | tail -5` — expected: all pass.
Run: `swift test 2>&1 | tail -3` — expected: every test passes.

```bash
git add Sources/T2SCore/Render/SynthesisEngine.swift Sources/T2SCore/Render/FakeEngine.swift Sources/T2SAudio/RoutedEngine.swift Tests/T2SCoreTests/Render/FakeEngineTests.swift Tests/T2SAudioTests/RoutedEngineTests.swift
git commit -m "Plan 14 Task 2: engines can stream — SynthesisChunk, synthesizeStreaming with a whole-render default, a fake that streams under test control, the router forwarding"
```

---

### Task 3: The scheduler forwards pieces

**Files:**
- Modify: `Sources/T2SCore/Render/RenderScheduler.swift`
- Test: `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift`

**Interfaces:**
- Consumes: `SynthesisChunk`, `synthesizeStreaming` (Task 2).
- Produces: `RenderRequest.stream: Bool` (init parameter, default false);
  `RenderEvent.piece(documentID: UUID, utteranceIndex: Int, audio: PCMAudio, ordinal: Int, isLast: Bool)`.

- [ ] **Step 1: Write the failing tests**

In `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift`, extend the `request` helper with a
`stream: Bool = false` parameter passed through, and add:

```swift
    /// A streaming request yields its pieces as they finish, then the same `.rendered` a whole
    /// render would, and the store holds the concatenation.
    @Test func aStreamingRequestForwardsPiecesThenRenders() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1, pieceCount: 3), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abcdefghi", stream: true)])
        let got = await events
        #expect(got.count == 5)                                       // 3 pieces, rendered, idle
        for (i, e) in got.prefix(3).enumerated() {
            guard case .piece(doc, 0, let audio, i, i == 2) = e else { Issue.record("piece \(i): \(e)"); continue }
            #expect(abs(audio.duration - 0.3) < 1e-9)
        }
        guard case .rendered(let r) = got[3] else { Issue.record("no rendered: \(got[3])"); return }
        #expect(abs(r.duration - 0.9) < 1e-9 && r.wordTimings.count == 1)
        #expect(try await store.read(key(0))?.duration == 0.9)
    }

    /// A cache hit never streams: the clip is on disk, the player reads it from there.
    @Test func aStreamingRequestThatIsACacheHitYieldsNoPieces() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        try await store.write(.silence(seconds: 1), for: key(0))
        let s = RenderScheduler(engine: FakeEngine(pieceCount: 2), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "already", stream: true)])
        let got = await events
        #expect(got.count == 2)                                       // rendered (from cache), idle
    }

    /// An engine that fails mid-stream: the pieces already forwarded stand, the key gets the
    /// failure silence, and `.failed` then `.rendered` follow as for any failure (spec §6).
    @Test func aStreamThatFailsStillRendersTheFailureSilence() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 2)
        await engine.fail(on: "boom")
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "boom", stream: true)])
        let got = await events
        #expect(got.count == 3)                                       // failed, rendered(silence), idle
        guard case .failed = got[0], case .rendered(let r) = got[1] else { Issue.record("\(got)"); return }
        #expect(abs(r.duration - RenderScheduler.failureSilenceSeconds) < 1e-9)
    }
```
(`FakeEngine.fail(on:)` throws from `synthesize`, which the fake's stream calls first, so no piece
precedes the failure; that is the case the coordinator cares about most — nothing enqueued, then
silence. A fake that fails *after* a piece is not needed here.)

- [ ] **Step 2: Run them to see them fail to compile**

Run: `swift test --filter RenderSchedulerTests 2>&1 | tail -5`
Expected: `extra argument 'stream' in call` / `type 'RenderEvent' has no member 'piece'`.

- [ ] **Step 3: The request flag and the event**

In `RenderRequest`, add `public var stream: Bool` with the doc comment "Render in pieces and forward
each as a `.piece` event: the utterance the player is waiting on (Plan 14)." and an init parameter
`stream: Bool = false`. In `RenderEvent`, add before `.rendered`:

```swift
    /// A piece of a streaming render, in order, before its `.rendered`; the pieces concatenate to
    /// the clip stored under the key. `isLast` marks the piece the player's completion belongs to.
    case piece(documentID: UUID, utteranceIndex: Int, audio: PCMAudio, ordinal: Int, isLast: Bool)
```

- [ ] **Step 4: The streaming render path**

In `renderWhileHoldingLease`, replace the synthesis block

```swift
        var events: [RenderEvent] = []
        let t0 = timeSource.now()
        var result: SynthesisResult
        do {
            result = try await engine.synthesize(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID))
            let synthSeconds = timeSource.now() - t0
            if result.audio.duration > 0 { record(rtf: synthSeconds / result.audio.duration) }
        } catch {
```
with
```swift
        var events: [RenderEvent] = []
        let t0 = timeSource.now()
        var result: SynthesisResult
        do {
            result = request.stream
                ? try await streamed(request)
                : try await engine.synthesize(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID))
            let synthSeconds = timeSource.now() - t0
            if result.audio.duration > 0 { record(rtf: synthSeconds / result.audio.duration) }
        } catch {
```
and add the private method:

```swift
    /// Renders in pieces, yielding each to the events stream the moment it arrives — the player is
    /// waiting on this utterance — and returns the whole for the store: the pieces' concatenation
    /// and the timings the engine folded over it.
    private func streamed(_ request: RenderRequest) async throws -> SynthesisResult {
        var pieces: [PCMAudio] = []
        var timings: [WordTiming] = []
        for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID)) {
            switch chunk {
            case .piece(let audio, let ordinal, let isLast):
                pieces.append(audio)
                continuation.yield(.piece(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex,
                                          audio: audio, ordinal: ordinal, isLast: isLast))
            case .finished(let wordTimings):
                timings = wordTimings
            }
        }
        let sampleRate = pieces.first?.sampleRate ?? PCMAudio.defaultSampleRate
        return SynthesisResult(audio: PCMAudio(sampleRate: sampleRate, samples: pieces.flatMap(\.samples)), wordTimings: timings)
    }
```

- [ ] **Step 5: Run the suite, then everything, and commit**

Run: `swift test --filter RenderSchedulerTests 2>&1 | tail -5` — expected: all pass.
Run: `swift test 2>&1 | tail -3` — expected: every test passes.

```bash
git add Sources/T2SCore/Render/RenderScheduler.swift Tests/T2SCoreTests/Render/RenderSchedulerTests.swift
git commit -m "Plan 14 Task 3: the scheduler forwards pieces — a streaming request yields .piece events as they finish and stores their concatenation"
```

---

### Task 4: The coordinator plays the first piece

**Files:**
- Modify: `Sources/T2SAudio/PlaybackCoordinator.swift` — new state, `replan()`, `fill()`, `seek`, `load`, `apply(_:)`
- Test: `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`

**Interfaces:**
- Consumes: `RenderRequest.stream`, `RenderEvent.piece` (Task 3); `AudioPlaying.enqueue(_:tag:isFinal:)` (Task 1); `FakeEngine(pieceCount:)`, `holdBetweenPieces()`, `releasePiece()`, `stopHoldingBetweenPieces()` (Task 2).
- Produces: no public API change. Internal state: `streaming: (index: Int, nextOrdinal: Int, pendingDropSamples: Int)?`.

- [ ] **Step 1: Write the failing tests**

In `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`, add a second fixture beside `fixture(...)`:

```swift
    /// The same three sentences, rendered by a fake that streams each utterance in `pieces` pieces
    /// and parks between them, so a test can see the player start on the first piece.
    func streamingFixture(pieces: Int = 3) async
        -> (PlaybackCoordinator, FakePlayer, FakeEngine, InMemoryAudioStore, Document, Timeline) {
        let block = SourceBlock(text: "Alpha one. Beta two. Gamma three.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: pieces)
        await engine.holdBetweenPieces()
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let player = FakePlayer()
        let c = PlaybackCoordinator(engine: engine, store: store, player: player, playheadStore: MemoryPlayheadStore(), timeSource: ManualTimeSource(),
                                    configuration: CoordinatorConfiguration(windowSeconds: 60, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        return (c, player, engine, store, Document(title: "T", sourceType: .article), timeline)
    }

    /// Waits until the player holds `count` buffers, or fails after a second.
    func waitForBuffers(_ player: FakePlayer, _ count: Int) async {
        for _ in 0 ..< 200 where player.enqueuedTags.count < count { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(player.enqueuedTags.count == count, "buffers: \(player.enqueuedTags)")
    }
```

and the tests:

```swift
    /// Audit #2: a tap on an unrendered position plays after the head's first piece, not after the
    /// whole utterance — the player holds one buffer, is playing, and nothing else is queued.
    @Test func playStartsOnTheHeadsFirstPiece() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture()
        await engine.hold()                                          // nothing renders until release
        c.load(doc, timeline: timeline)
        await c.play()
        #expect(c.state == .catchingUp)
        await engine.release()                                       // utterance 0 starts streaming; piece 0 arrives, piece 1 parks
        await waitForBuffers(player, 1)
        await c.settle()
        #expect(c.state == .playing && player.isPlaying)
        #expect(player.enqueuedTags == [0])
        #expect(player.queue.first?.isFinal == false)
        // The next utterance is never enqueued behind an unfinished stream.
        await engine.releasePiece()                                  // piece 1
        await waitForBuffers(player, 2)
        #expect(player.enqueuedTags == [0, 0])
        await engine.stopHoldingBetweenPieces()                      // piece 2 (last) and everything after
        await c.waitForRenderIdle()
        #expect(player.enqueuedTags.prefix(4) == [0, 0, 0, 1])       // the last piece, then utterance 1 whole (it was not streamed)
        #expect(player.queue.filter { $0.tag == 0 }.last?.isFinal == true)
        #expect(c.timeline?[utterance: 0].wordTimings?.isEmpty == false)
    }

    /// The playhead moves through a streamed head as the pieces play, and the segment finishes
    /// once, after the last piece.
    @Test func aStreamedHeadPlaysThroughAsOneSegment() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.stopHoldingBetweenPieces()                      // stream freely
        c.load(doc, timeline: timeline)
        await c.play()
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        player.advance(seconds: 0.7); c.tick()
        #expect(c.playhead == Playhead(utteranceIndex: 0, offset: 0.7))
        player.advance(seconds: 0.4); await c.settle(); c.tick()     // past 1.0 s: utterance 1
        #expect(c.playhead.utteranceIndex == 1)
        #expect(abs(c.playhead.offset - 0.1) < 1e-9)
    }

    /// A seek into the middle of an unrendered utterance drops the offset from the streamed pieces,
    /// so `consumedSeconds` still maps to the playhead.
    @Test func aSeekIntoAStreamedHeadDropsTheOffset() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.stopHoldingBetweenPieces()
        await engine.hold()                                          // nothing renders until the seek has happened
        c.load(doc, timeline: timeline)
        await c.seek(to: Playhead(utteranceIndex: 0, offset: 0.6))   // "Alpha one." is 1.0 s: 0.4 s remain
        await engine.release()                                       // the head streams from its start; the coordinator drops 0.6 s
        await c.play()
        await c.waitForRenderIdle()
        #expect(player.queuedRemaining > 0)
        let head = player.queue.filter { $0.tag == 0 }.reduce(0) { $0 + $1.remaining }
        #expect(abs(head - 0.4) < 1e-9)
        player.advance(seconds: 0.3); c.tick()
        #expect(abs(c.playhead.offset - 0.9) < 1e-9)
    }

    /// A stream the coordinator did not see from its first piece — the player was reset by a seek
    /// while it ran — is ignored; the `.rendered` that follows plays from the store as before.
    @Test func aStreamJoinedLateIsIgnoredAndTheStoreCopyPlays() async throws {
        let (c, player, engine, _, doc, timeline) = await streamingFixture(pieces: 2)
        await engine.hold()
        c.load(doc, timeline: timeline)
        await c.play()                                               // catching up on utterance 0
        await engine.release()
        await waitForBuffers(player, 1)                              // piece 0 in; piece 1 parked
        await c.seek(to: Playhead(utteranceIndex: 0, offset: 0))     // resets the player mid-stream
        #expect(player.enqueuedTags.isEmpty)
        await engine.stopHoldingBetweenPieces()                      // piece 1 arrives for a stream nobody follows
        await c.waitForRenderIdle()
        #expect(c.state == .playing)
        #expect(player.enqueuedTags.prefix(1) == [0])                // one whole buffer from the store, not a stray piece
        #expect(player.queue.first(where: { $0.tag == 0 })?.isFinal == true)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter PlaybackCoordinatorTests 2>&1 | tail -8`
Expected: compile errors for `pieceCount`/`holdBetweenPieces` are gone after Task 2; the tests fail on
assertions (`enqueuedTags == [0]` sees `[]`, `state == .playing` sees `.catchingUp`), or on
`player.queue.first?.isFinal` (Task 1's tuple exists).

- [ ] **Step 3: The streaming state**

In `PlaybackCoordinator`, beside `awaitingIndex`, add:

```swift
    /// The utterance whose pieces are being enqueued as the engine streams them (Plan 14): its index,
    /// the ordinal the next piece must carry, and the samples still to drop from its front (a seek
    /// into the middle of it). Nil when nothing streams — including a stream joined late, which is
    /// ignored until its `.rendered` puts the whole clip in the store.
    private var streaming: (index: Int, nextOrdinal: Int, pendingDropSamples: Int)?
```

`load(_:timeline:)` and `seek(to:)` set `streaming = nil` where they set `lastEnqueued = nil`.

- [ ] **Step 4: The head request streams**

In `replan()`, the head utterance streams when the player has nothing queued: change the request
mapping to

```swift
        // Nothing queued: the next `fill()` will wait on the head, so the head renders in pieces and
        // the first sound needs one short piece, not the whole utterance (audit #2).
        let streamIndex = queuedCount == 0 && streaming == nil ? headIndex : nil
        let requests = RenderPolicy.plan(input).map { job in
            RenderRequest(job: job,
                          key: renderKey(for: document, timeline: timeline, utteranceIndex: job.utteranceIndex),
                          spoken: timeline[utterance: job.utteranceIndex].spoken,
                          voiceID: document.voiceID ?? "default",
                          stream: job.utteranceIndex == streamIndex && job.tier == .playAhead)
        }
```

- [ ] **Step 5: `fill()` respects a stream**

At the top of `fill()`'s `while` loop, after computing `next`, add:

```swift
            // A streaming utterance owns the player until its last piece: enqueueing the utterance
            // after it now would play out of order.
            if let streaming, next > streaming.index { return }
```
and when `fill()` is about to enqueue `next` from the store while `streaming?.index == next` (the
stream's `.rendered` arrived before its last piece was enqueued — impossible in order, but the guard
is cheap): skip, `streaming` handles it: `if streaming?.index == next { return }` right after the
guard above.

- [ ] **Step 6: Pieces are enqueued as they arrive**

In `apply(_:)`, add a case before `.rendered`:

```swift
        case .piece(let documentID, let index, let audio, let ordinal, let isLast):
            guard let document, document.id == documentID, timeline != nil else { return }
            if streaming == nil {
                // A stream starts only at its first piece, only for the head, only when the player
                // holds nothing — otherwise the pieces would land behind or inside another segment.
                guard ordinal == 0, index == headIndex, queuedCount == 0 else { return }
                streaming = (index, 0, headStartConsumed < 0 ? Int((-headStartConsumed * audio.sampleRate).rounded()) : 0)
            }
            guard var s = streaming, s.index == index, s.nextOrdinal == ordinal else { return }
            var clip = audio
            if s.pendingDropSamples > 0 {
                let drop = min(clip.samples.count, s.pendingDropSamples)
                clip.samples.removeFirst(drop)
                s.pendingDropSamples -= drop
            }
            s.nextOrdinal += 1
            streaming = isLast ? nil : s
            if !clip.samples.isEmpty || isLast {
                player.enqueue(clip, tag: index, isFinal: isLast)
            }
            lastEnqueued = index
            awaitingIndex = nil
            if state == .catchingUp, !clip.samples.isEmpty {
                player.play()
                state = .playing
            }
            if isLast {
                chain { await self.fill() }                          // the rest of the window may follow now
            }
```

`.rendered` for a streamed utterance changes nothing (the pieces are already enqueued and
`lastEnqueued == index`), except that a failure mid-stream — `.rendered` arriving while
`streaming?.index == r.utteranceIndex` — must close the stream: at the top of the `.rendered` case,
after the existing guard, add

```swift
            if streaming?.index == r.utteranceIndex {
                // The engine stopped before its last piece (spec §6: silence under the key). Close the
                // segment so the player's completion can fire and the next utterance follows.
                streaming = nil
                player.enqueue(PCMAudio(sampleRate: PCMAudio.defaultSampleRate, samples: []), tag: r.utteranceIndex, isFinal: true)
            }
```
(`AudioPlayer.enqueue` with an empty buffer schedules a zero-frame buffer whose `.dataPlayedBack`
still fires; `FakePlayer` drains it on the next `advance`. Confirm both in the tests below.)

- [ ] **Step 7: The empty final buffer**

In `Tests/T2SAudioTests/AudioPlayerTests.swift`, add:

```swift
    /// A stream that ended early closes its segment with an empty final buffer; the completion still
    /// fires (Task 4's failure path).
    @Test func anEmptyFinalBufferStillCompletes() throws {
        let p = try AudioPlayer(manualRendering: true)
        var finished: [Int] = []
        p.onSegmentFinished = { finished.append($0) }
        p.enqueue(.silence(seconds: 0.3), tag: 3, isFinal: false)
        p.enqueue(PCMAudio(sampleRate: PCMAudio.defaultSampleRate, samples: []), tag: 3, isFinal: true)
        p.play()
        try p.renderOffline(seconds: 0.4)
        #expect(finished == [3])
    }
```
If `AVAudioPlayerNode.scheduleBuffer` rejects a zero-frame buffer (it may log and skip), make
`AudioPlayer.enqueue` handle `audio.samples.isEmpty && isFinal` by recording the completion directly:
in manual mode `manualSegments.append((tag, Double(scheduledFrames)))`; in live mode
`Task { @MainActor in self.onSegmentFinished?(tag) }` guarded by `generation` — and say which path
was needed in the report.

- [ ] **Step 8: Run the coordinator and player suites, then everything, and commit**

Run: `swift test --filter "PlaybackCoordinatorTests|AudioPlayerTests" 2>&1 | tail -6` — expected: all pass.
Run: `swift test 2>&1 | tail -3` — expected: every test passes (the end-to-end test now streams its
head through the real offline `AudioPlayer` — it must still finish).

```bash
git add Sources/T2SAudio/PlaybackCoordinator.swift Sources/T2SAudio/AudioPlayer.swift Tests/T2SAudioTests/PlaybackCoordinatorTests.swift Tests/T2SAudioTests/AudioPlayerTests.swift
git commit -m "Plan 14 Task 4: the coordinator plays the first piece — the head request streams when nothing is queued, pieces are enqueued as they arrive, playback starts on the first"
```

---

### Task 5: The Kokoro engine streams

**Files:**
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift` — `pieces(ids:owners:words:firstPieceCap:)`, a shared per-piece render+clean, `synthesizeStreaming`, `stream(_:emit:)`
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLSeam.swift` — `trimmedTail(_:budget:)`, `trimmedHead(_:cap:)`
- Modify: `App/T2SReader/System/GatedKokoroCoreMLEngine.swift` — forward `synthesizeStreaming`
- Test: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLSeamTests.swift`, `KokoroCoreMLEngineTests.swift`

**Interfaces:**
- Consumes: `SynthesisChunk` (Task 2); `KokoroCoreMLSeam.Cut`, `budgetSamples(for:)`, `KokoroCoreMLTailClick.removed(from:)`, `KokoroCoreMLTimingFold.Piece`, `timedTokens`, `KokoroTokenTimingMapper.map`.
- Produces: `KokoroCoreMLEngine.streamingFirstPieceTokenCount = 48`;
  `static func pieces(ids:owners:words:firstPieceCap: Int? = nil)`;
  `KokoroCoreMLSeam.trimmedTail(_ audio: [Float], budget: Int) -> (audio: [Float], dropped: Int)`;
  `KokoroCoreMLSeam.trimmedHead(_ audio: [Float], cap: Int) -> (audio: [Float], dropped: Int)`;
  `nonisolated func synthesizeStreaming(_:)` on the engine.

- [ ] **Step 1: Check the constraint before touching the package**

Run: `ps aux | grep '[x]codebuild' | grep -c T2SKokoro; df -h . | tail -1`
If the count is not 0 or free space is under 4 GB, stop and report BLOCKED — the controller decides
whether to wait or to defer this task. Otherwise continue.

- [ ] **Step 2: Write the failing seam tests**

In `KokoroCoreMLSeamTests.swift` (follow its existing helpers for building sample arrays), add:

```swift
    /// Streaming finalizes a piece before the next exists: its tail silence is cut to the budget on
    /// its own, and the next piece's lead-in is cut on its own, up to its BOS frames.
    @Test func tailAndHeadAreTrimmedIndependently() {
        let loud: [Float] = Array(repeating: 0.5, count: 100)
        let quiet: [Float] = Array(repeating: 0.001, count: 1000)
        let tail = KokoroCoreMLSeam.trimmedTail(loud + quiet, budget: 300)
        #expect(tail.dropped == 700 && tail.audio.count == 400)
        let untouched = KokoroCoreMLSeam.trimmedTail(loud + quiet, budget: .max)
        #expect(untouched.dropped == 0)
        let head = KokoroCoreMLSeam.trimmedHead(quiet + loud, cap: 250)
        #expect(head.dropped == 250 && head.audio.count == 850)
        let all = KokoroCoreMLSeam.trimmedHead(quiet + loud, cap: 5000)
        #expect(all.dropped == 1000 && all.audio.first == 0.5)
        let silentOnly = KokoroCoreMLSeam.trimmedTail(quiet, budget: 300)
        #expect(silentOnly.dropped == 0)                             // never emptied: nothing but silence is left alone
    }
```

- [ ] **Step 3: Write the failing cutter test**

In `KokoroCoreMLEngineTests.swift`, beside `keepsAShortUtteranceInOnePiece`, add (using the file's
`appendPlainWords` helper to build ids/owners/words for N plain words of, say, 8 ids each):

```swift
    /// The streamed head's first piece is short — `streamingFirstPieceTokenCount` ids at most, cut at
    /// the best boundary before that — so the first sound needs one small call; the pieces after it
    /// are cut at the usual cap.
    @Test func aFirstPieceCapMakesTheFirstPieceShort() throws {
        var ids: [Int32] = [], owners: [Int] = [], words: [MToken] = []
        Self.appendPlainWords(30, idsPerWord: 8, into: &ids, owners: &owners, words: &words)   // 240 ids
        let whole = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        let streamed = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words,
                                                     firstPieceCap: KokoroCoreMLEngine.streamingFirstPieceTokenCount)
        #expect(whole.count == 2)
        #expect(streamed.count == 3)
        #expect(streamed[0].ids.count <= KokoroCoreMLEngine.streamingFirstPieceTokenCount)
        #expect(streamed[0].ids.count == 48)                          // six whole words
        #expect(streamed.flatMap(\.ids) == ids)
        #expect(streamed[1].cut == .word)
    }
```
(If `appendPlainWords`'s signature differs, adapt the call; the assertions are what matter.)

- [ ] **Step 4: Build the package's non-model suites to see them fail**

Run, from `Packages/T2SKokoro`:
```bash
xcodebuild test -scheme T2SKokoro -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath .build/DerivedData -only-testing:T2SKokoroTests/KokoroCoreMLSeamTests -only-testing:T2SKokoroTests/KokoroCoreMLEngineTests 2>&1 | grep -E "error:|Suite |Executed|TEST (SUCCEEDED|FAILED)" | grep -v "/checkouts/"
```
Expected: compile errors for `trimmedTail`, `trimmedHead`, `firstPieceCap`, `streamingFirstPieceTokenCount`.

- [ ] **Step 5: The seam helpers**

In `KokoroCoreMLSeam.swift`, add:

```swift
    /// The tail of a piece that is emitted before its successor exists (a streamed head, Plan 14):
    /// its trailing silence cut to at most `budget` samples. Never emptied, never touched when the
    /// piece is silence throughout.
    static func trimmedTail(_ audio: [Float], budget: Int) -> (audio: [Float], dropped: Int) {
        guard budget < .max else { return (audio, 0) }
        var tail = 0
        while tail < audio.count, abs(audio[audio.count - 1 - tail]) < silence { tail += 1 }
        guard tail < audio.count, tail > budget else { return (audio, 0) }
        let dropped = tail - budget
        return (Array(audio.dropLast(dropped)), dropped)
    }

    /// The head of a piece that follows one already emitted: its lead-in silence cut, at most `cap`
    /// samples (the BOS token's own frames — the fold counts from there). Never emptied.
    static func trimmedHead(_ audio: [Float], cap: Int) -> (audio: [Float], dropped: Int) {
        var head = 0
        while head < audio.count, abs(audio[head]) < silence { head += 1 }
        guard head < audio.count else { return (audio, 0) }
        let dropped = min(head, max(0, cap))
        return (Array(audio.dropFirst(dropped)), dropped)
    }
```

- [ ] **Step 6: The first-piece cap**

In `KokoroCoreMLEngine`, add beside `maxPieceTokenCount`:

```swift
    /// How many ids the first piece of a *streamed* utterance may carry: about three seconds of
    /// speech, which the 7 s bucket renders in about a second on an A13 — the first sound. The
    /// pieces after it are cut at ``maxPieceTokenCount`` as usual.
    static let streamingFirstPieceTokenCount = 48
```

Change `pieces(ids:owners:words:)` to `pieces(ids:owners:words:firstPieceCap: Int? = nil)`: the cap
for the piece being packed is `firstPieceCap` while `packed.isEmpty` and `firstPieceCap != nil`, else
`maxPieceTokenCount`; `bestCutIndex(in:)` gains a `cap: Int` parameter used for its "at least half a
call's worth" minimum (`idsThrough * 2 >= cap`) and every existing caller passes `maxPieceTokenCount`.
The `guard group.ids.count <= maxPieceTokenCount` stays as it is (a single word longer than the
first-piece cap simply becomes the first piece on its own — `while currentCount + group.ids.count > cap, !current.isEmpty`
never cuts an empty `current`).

- [ ] **Step 7: The shared per-piece render and the streaming path**

Extract from `synthesize`'s loop a private method that renders one `Piece` (with the overflow
splitting) and removes the tail click from each rendered sub-piece:

```swift
    /// One piece of an utterance rendered — split on overflow — with the tail click removed from
    /// every rendered sub-piece: what both `synthesize` and `stream` start from.
    private func renderedPieces(_ piece: Piece, isFinal: Bool, words: [MToken], tokenizer: KokoroTokenizer, loaded: Loaded)
        throws -> [(piece: Piece, result: KokoroPipelineResult, audio: [Float])] {
        try renderWithSplitting(piece, isFinal: isFinal, words: words, tokenizer: tokenizer, loaded: loaded).map { subPiece, result in
            (subPiece, result, options.removeTailClick ? KokoroCoreMLTailClick.removed(from: result.audio) : result.audio)
        }
    }
```
and use it in `synthesize` (its loop keeps the rest of its join exactly as it is — `cleaned` comes
from the tuple). Then add:

```swift
    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `synthesize` in pieces, each finalized on its own — tail click gone, tail silence cut to the
    /// budget of the cut that follows it, lead-in cut up to its BOS frames — and emitted the moment
    /// it is, so the first sound needs the first small piece only. The pieces are butted, not
    /// crossfaded: with both sides trimmed the join lands inside silence. The timings are folded
    /// over the concatenation, exactly as `synthesize` folds over its join.
    private func stream(_ request: SynthesisRequest, emit: @Sendable (SynthesisChunk) -> Void) async throws {
        guard let id = KokoroVoiceID(rawValue: request.voiceID), id.engineID == engineID else {
            throw KokoroCoreMLError.voiceNotForThisEngine(request.voiceID)
        }
        guard !request.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.failed("nothing to speak")
        }
        try Task.checkCancellation()
        guard let voiceURL = resources.voices[id.voice] else { throw KokoroCoreMLError.unknownVoice(id.voice) }

        let loaded = try await load()
        let tokenizer = try tokenizer(voice: id.voice, url: voiceURL)
        let words = MLX.Device.withDefaultDevice(.cpu) {
            g2p(british: id.voice.hasPrefix("b")).phonemize(text: request.spoken).1
        }
        let (phonemes, ownersByCharacter) = Self.phonemeWalk(words)
        let tokenization = tokenizer.tokenize(phonemes: phonemes, ownersByCharacter: ownersByCharacter)
        let pieces = try Self.pieces(ids: tokenization.ids, owners: tokenization.owners, words: words,
                                     firstPieceCap: Self.streamingFirstPieceTokenCount)

        // Every rendered sub-piece, in order, with the cut that closes it (the next sub-piece's cut).
        var rendered: [(piece: Piece, result: KokoroPipelineResult, audio: [Float])] = []
        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            rendered += try renderedPieces(piece, isFinal: index == pieces.count - 1, words: words, tokenizer: tokenizer, loaded: loaded)
            // Emit everything finalizable so far: a sub-piece is final once the cut after it is known,
            // which is as soon as the next sub-piece exists — or now, for the utterance's last.
            try emitFinalized(&rendered, upTo: index == pieces.count - 1 ? rendered.count : rendered.count - 1, emit: emit)
        }
        emit(.finished(wordTimings: finishTimings(words: words, spoken: request.spoken)))
    }
```

Keep the per-utterance fold state (`folds`, `emittedSamples`, `ordinal`) in a small private struct
`StreamState` held for the duration of `stream` (pass it inout to `emitFinalized`, or make
`emitFinalized`/`finishTimings` closures inside `stream` — the implementer chooses; keep it readable).
`emitFinalized` does, for each sub-piece `k` not yet emitted whose successor's cut is known (or which
is the utterance's last):

1. `var audio = rendered[k].audio`; `var droppedHead = 0`
2. if `k > 0` and `rendered[k].piece.cut != .none`: `(audio, droppedHead) = KokoroCoreMLSeam.trimmedHead(audio, cap: bosSamples)` where `bosSamples = (rendered[k].result.tokenDurationFrames.first ?? 0) * PipelineConstants.samplesPerDurationFrame` — only when `options.trimSeams`.
3. if `k` is not the utterance's last: `let (trimmed, droppedTail) = KokoroCoreMLSeam.trimmedTail(audio, budget: KokoroCoreMLSeam.budgetSamples(for: rendered[k + 1].piece.cut))`; `audio = trimmed` — only when `options.trimSeams`; else `droppedTail = 0`.
4. `folds.append(KokoroCoreMLTimingFold.Piece(owners: piece.owners, frames: result.tokenDurationFrames, offsetSeconds: Double(emittedSamples - droppedHead) / rate, trimmedTailSeconds: Double(droppedTail) / rate))` — the offset is where the untrimmed audio would have begun (the fold counts BOS frames from there), exactly as `synthesize` computes it.
5. `guard !audio.isEmpty, audio.allSatisfy(\.isFinite) else { throw KokoroCoreMLError.emptyAudio }`
6. `emit(.piece(PCMAudio(sampleRate: rate, samples: audio), ordinal: ordinal, isLast: isUtteranceLast))`; `emittedSamples += audio.count`; `ordinal += 1`; mark `k` emitted.

`finishTimings` builds `KokoroCoreMLTimingFold.timedTokens(words.map { KokoroToken(text: $0.text, whitespace: $0.whitespace, start: nil, end: nil) }, pieces: folds)` and maps with
`KokoroTokenTimingMapper.map(timed, spoken: request.spoken, duration: Double(emittedSamples) / rate)`.

Note the utterance-final sub-piece is emitted with `isLast: true` and no tail trim (the model's
end-of-input pause stays, as in `synthesize`).

- [ ] **Step 8: The gate forwards**

In `App/T2SReader/System/GatedKokoroCoreMLEngine.swift`, add:

```swift
    nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in try await self.engine().synthesizeStreaming(request) { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```

- [ ] **Step 9: A model-gated streaming test, for the machine that can run it**

In `KokoroCoreMLEngineTests.swift`, add (it skips here — no model files in this worktree):

```swift
    /// The streamed render and the whole render of one long passage agree where it matters: the
    /// same words timed within ±100 ms (spec §7.4), the pieces concatenating to the stored clip, and
    /// a first piece short enough to be the first sound.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func streamsALongPassageInPiecesThatFoldToTheSameTimings() async throws {
        let engine = try await Self.engineWithRealResources()
        let spoken = "It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness, it was the epoch of belief, it was the epoch of incredulity."
        let request = SynthesisRequest(spoken: spoken, voiceID: Self.voiceID("af_heart"))
        var pieces: [PCMAudio] = []
        var timings: [WordTiming] = []
        for try await chunk in engine.synthesizeStreaming(request) {
            switch chunk {
            case .piece(let audio, _, _): pieces.append(audio)
            case .finished(let t): timings = t
            }
        }
        #expect(pieces.count >= 2)
        #expect(pieces[0].duration < 5)                              // the first sound, not the whole passage
        let whole = try await engine.synthesize(request)
        #expect(timings.count == whole.wordTimings.count)
        for (a, b) in zip(timings, whole.wordTimings) { #expect(abs(a.start - b.start) < 0.1) }
        let total = pieces.reduce(0) { $0 + $1.duration }
        #expect(abs(total - whole.audio.duration) < 0.5)
    }
```

- [ ] **Step 10: Build and run the non-model suites; commit**

Run the Step 4 command again. Expected: `KokoroCoreMLSeamTests` and `KokoroCoreMLEngineTests` pass
(the model-gated tests are reported skipped), `TEST SUCCEEDED`. If disk or another session's run
blocks it, stop and report BLOCKED with the state (`ps`, `df`).

```bash
git add Packages/T2SKokoro App/T2SReader/System/GatedKokoroCoreMLEngine.swift
git commit -m "Plan 14 Task 5: the Kokoro engine streams — a short first piece, every piece finalized before it is emitted, the timings folded over the concatenation"
```

---

### Task 6: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (§3.3, §3.5, §3.6, header rev 15, changelog)
- Modify: `docs/superpowers/specs/2026-09-08-performance-audit.md` (progress note)
- Modify: `docs/HANDOFF.md` (a "Resume here (2026-09-08) — Plan 14" section above the Plan 13 one; the `_Last updated_` line)

- [ ] **Step 1: The spec**

§3.3, after "Seeking to an unrendered position re-prioritizes the render queue there and begins
playback in roughly a second, at Kokoro's measured throughput.", add:

```
**The head streams (rev 15).** The utterance the player is waiting on is rendered in pieces — a first
piece of about three seconds, then the rest at the usual cap — and each piece is enqueued the moment
it is rendered, so the first sound follows one short synthesis call rather than the whole utterance
(the performance audit's #2). Every other utterance in the window renders whole; the store holds the
pieces' concatenation under the same key either way.
```

§3.5, after "Buffers are scheduled per utterance for gapless playback.", add: "A streamed head is
several buffers under one tag; the segment's completion fires after the buffer marked final (rev 15)."

§3.6, in the bidirectional-rate bullet or beside it: nothing changes.

Header line: `rev 14` → `rev 15`. Changelog, above the rev 14 entry:

```
**rev 15 (2026-09-08)** — Plan 14: streaming the first sound
- **§3.3, §3.5** the head utterance renders in pieces (`SynthesisEngine.synthesizeStreaming`,
  `RenderEvent.piece`, `AudioPlaying.enqueue(_:tag:isFinal:)`); the first sound needs one short
  call. The Kokoro engine's first streamed piece is 48 ids (~3 s).
```

- [ ] **Step 2: The audit's progress note**

Under §2's progress note, add: "**Plan 14 (2026-09-08):** #2 done — the head streams; first sound
after the first ~3 s piece (~1 s on an A13 in the 7 s bucket). The 3 s bucket (#9) would halve that."

- [ ] **Step 3: HANDOFF**

Change the `_Last updated_` line to name Plan 14 and the worktree `.worktrees/plan-14-streaming` off
`origin/dev` @ 4056ccd, and add above "## Resume here (2026-09-08) — Plan 13":

```
## Resume here (2026-09-08) — Plan 14

Plan 14 (`docs/superpowers/plans/2026-09-08-plan-14-streaming-first-sound.md`) streams the head
utterance: `SynthesisEngine.synthesizeStreaming` (Task 2; default wraps `synthesize`),
`RenderRequest.stream` + `RenderEvent.piece` (Task 3), `AudioPlaying.enqueue(_:tag:isFinal:)` (Task 1),
`PlaybackCoordinator` enqueuing pieces as they arrive and starting playback on the first (Task 4), and
the Kokoro engine rendering a 48-id first piece and finalizing each piece before emitting it (Task 5).
Only the utterance the player is waiting on streams; the cache, Prepare and the prime are unchanged.

**Owed:** the model-backed streaming test (`streamsALongPassageInPiecesThatFoldToTheSameTimings()`)
and the quality probe on the streamed join — this Mac cannot run either (disk); the phone is the test.

**The phone listen.** Tap play on a book you have never played, skip forward 30 s twice, jump to a
late chapter, tap a word far down the page: sound should start within about a second each time, and
the first sentence after a tap should flow into its second piece without a hole or a tick. If the
first sentence sounds cut in two, the streamed join's tail budget (`KokoroCoreMLSeam.budgetSamples`)
is the knob; if the highlight drifts in the first sentence only, the fold's `offsetSeconds` for the
streamed pieces is.

**Next:** the 3 s bucket (audit #9) to halve the first sound again; then the open path (#5) and the
tick churn (#7).
```

- [ ] **Step 4: Whole suite, the app build if disk allows, commit**

Run: `swift test 2>&1 | tail -3` — expected: every test passes.
Run: `df -h . | tail -1` — if ≥ 4 GB free: `scripts/build-app.sh 2>&1 | grep -E "BUILD|error:" | tail -3`
(expected `** BUILD SUCCEEDED **`); otherwise skip and say so in the report (the controller runs it
before merging).

```bash
git add docs/
git commit -m "Plan 14 Task 6: docs — spec §3.3/§3.5 and rev 15, the audit's progress note, HANDOFF resume section with the phone listen"
```

Integration (the controller, not the task): rebase onto `origin/dev` if it moved, `swift test`, the
app build, then `git push origin HEAD:dev` (a fast-forward) as Plan 13 was merged.
