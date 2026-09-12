# Eco Voice Mirrors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the hosted Kokoro route ahead of playback on the $5 Heroku Eco plan by running four identical Eco apps and rendering up to four utterances at once across them.

**Architecture:** The render scheduler, today strictly serial, learns to take a bounded batch of same-tier requests and render them concurrently when the engine says it can; on-device engines say 1, so nothing changes for them. The HTTP engine holds one endpoint per mirror with its own rate limiter, spreads a batch round-robin, walks a request past a busy mirror, and cuts text over Eco's measured ceiling at clause boundaries. One script deploys the same subtree commit to every mirror and verifies each.

**Tech Stack:** Swift 6 (SwiftPM, Swift Testing), FastAPI on Python 3.12, Heroku CLI, bash.

**Spec:** `docs/superpowers/specs/2026-09-11-eco-voice-mirrors-design.md`

## Global Constraints

- Eco only. The deploy script scales to `eco` and nothing else; no add-ons, no pinger, no tier above Eco.
- The bearer token, request text, and audio are never logged, on any mirror or in the deploy script.
- Mirrors are identical: same build, same model digests, same key.
- `maxRequestCharacters` is `180`.
- Width 1 must leave the existing scheduler suite passing unchanged: that is the on-device regression guard.
- Swift targets compile in Swift 6 language mode (`.swiftLanguageMode(.v6)`); tests are Swift Testing (`@Test`, `#expect`, `#require`).
- Swift tests: `swift test --filter <Suite>` from the repository root. Server tests: `cd Server/HerokuVoice && PYTHONPATH=. /tmp/t2s-heroku-voice-venv/bin/python -m pytest tests -q`.
- Every commit stages only the task's own files. Commit messages are declarative sentences in the repository's style, no `feat:` prefixes.

## File Map

| File | Responsibility |
|---|---|
| `Sources/T2SCore/Segment/ClauseSplitter.swift` (new) | The one rule for cutting overlong text: clause, then whitespace, then a hard cut that never splits a surrogate pair. |
| `Sources/T2SCore/Segment/Segmenter.swift` | `split` calls `ClauseSplitter`; behaviour byte-identical. |
| `Sources/T2SCore/Render/SynthesisEngine.swift` | `maxConcurrentRenders(for:)`, default 1. |
| `Sources/T2SCore/Render/FakeEngine.swift` | Reports a configurable width. |
| `Sources/T2SCore/Render/RenderScheduler.swift` | Renders a same-tier batch concurrently; RTF per batch. |
| `Sources/T2SAudio/HTTPVoiceEngine.swift` | `endpoints`, per-endpoint limiters, round-robin, 429 walk, clause split. |
| `Sources/T2SAudio/RoutedEngine.swift` | Forwards the width; cache key includes every endpoint. |
| `Sources/T2SApp/Preferences/CloudVoiceSettings.swift` | One endpoint per line. |
| `App/T2SReader/Preferences/CloudVoicesPage.swift` | Vertical endpoint field and caption. |
| `Server/HerokuVoice/voice_service/web.py` | 422 without echoing the request. |
| `Server/HerokuVoice/scripts/mirrors.sh` (new) | Idempotent N-app Eco deploy and verify. |
| `Server/HerokuVoice/README.md` | Mirrors section. |
| `docs/HANDOFF.md`, `docs/superpowers/evidence/` | The live run's record. |

---

### Task 1: ClauseSplitter

**Files:**
- Create: `Sources/T2SCore/Segment/ClauseSplitter.swift`
- Modify: `Sources/T2SCore/Segment/Segmenter.swift:106-133` (the private `split`)
- Test: `Tests/T2SCoreTests/ClauseSplitterTests.swift` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `ClauseSplitter.cuts(in text: String, maxLength: Int) -> [NSRange]` (UTF-16 ranges covering `text` exactly, in order, untrimmed) and `ClauseSplitter.pieces(of text: String, maxLength: Int) -> [String]` (trimmed, empties dropped). Task 6 uses `pieces`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/T2SCoreTests/ClauseSplitterTests.swift`:

```swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct ClauseSplitterTests {
    @Test func textWithinTheLimitIsOnePiece() {
        #expect(ClauseSplitter.pieces(of: "Short enough.", maxLength: 80) == ["Short enough."])
    }

    @Test func cutsAtTheLastClauseBoundaryBeforeTheLimit() {
        let text = "one two three, four five six; seven eight nine, ten"
        let pieces = ClauseSplitter.pieces(of: text, maxLength: 20)
        #expect(pieces == ["one two three,", "four five six;", "seven eight nine,", "ten"])
        #expect(pieces.allSatisfy { ($0 as NSString).length <= 20 })
    }

    @Test func fallsBackToWhitespaceThenAHardCut() {
        #expect(ClauseSplitter.pieces(of: "alpha beta gamma delta", maxLength: 11) == ["alpha beta", "gamma", "delta"])
        #expect(ClauseSplitter.pieces(of: "abcdefghij", maxLength: 4) == ["abcd", "efgh", "ij"])
    }

    @Test func aHardCutNeverSplitsASurrogatePair() {
        let text = "ab😀cd"                                          // 😀 is two UTF-16 units
        let pieces = ClauseSplitter.pieces(of: text, maxLength: 3)
        #expect(pieces == ["ab", "😀c", "d"])                        // the pair moved whole into the next piece
        #expect(pieces[1].unicodeScalars.contains("😀"))
    }

    @Test func cutsCoverTheTextExactlyAndInOrder() {
        let text = "First clause here, second clause there; third clause, and a fourth one."
        let cuts = ClauseSplitter.cuts(in: text, maxLength: 25)
        let ns = text as NSString
        #expect(cuts.first?.location == 0)
        #expect(cuts.last.map { $0.location + $0.length } == ns.length)
        for (a, b) in zip(cuts, cuts.dropFirst()) { #expect(a.location + a.length == b.location) }
        #expect(cuts.allSatisfy { $0.length <= 25 })
    }

    @Test func whitespaceOnlyPiecesAreDropped() {
        // "one," then a window of four spaces, cut at its last space: that piece trims to nothing.
        #expect(ClauseSplitter.pieces(of: "one,    two", maxLength: 4) == ["one,", "two"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ClauseSplitterTests`
Expected: compilation fails, `cannot find 'ClauseSplitter' in scope`.

- [ ] **Step 3: Implement the splitter**

Create `Sources/T2SCore/Segment/ClauseSplitter.swift`:

```swift
import Foundation

/// The one rule for cutting text that is too long for a single call: at the last clause boundary
/// before the limit, else the last whitespace, else a hard cut that never divides a surrogate
/// pair. The segmenter applies it to an overlong sentence; the cloud engine applies it to an
/// utterance longer than a hosted request may carry. Lengths are UTF-16 units.
public enum ClauseSplitter {
    public static let clauseBoundaries = CharacterSet(charactersIn: ";:,—–")

    /// Ranges into `text`, in order, covering it exactly. Untrimmed: a piece after a whitespace cut
    /// starts with that whitespace. `maxLength` must be at least 2 so a hard cut can always make
    /// progress past a surrogate pair.
    public static func cuts(in text: String, maxLength: Int) -> [NSRange] {
        precondition(maxLength >= 2, "maxLength must be at least 2")
        let ns = text as NSString
        guard ns.length > maxLength else { return [NSRange(location: 0, length: ns.length)] }
        var ranges: [NSRange] = []
        var start = 0
        while ns.length - start > maxLength {
            let window = NSRange(location: start, length: maxLength)
            var cut = ns.rangeOfCharacter(from: clauseBoundaries, options: .backwards, range: window).location
            if cut != NSNotFound && cut > start { cut += 1 }         // the mark stays with its clause
            if cut == NSNotFound || cut <= start {
                cut = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: window).location
            }
            if cut == NSNotFound || cut <= start {
                cut = start + maxLength
                if cut - 1 > start && CFStringIsSurrogateHighCharacter(ns.character(at: cut - 1)) { cut -= 1 }
            }
            ranges.append(NSRange(location: start, length: cut - start))
            start = cut
        }
        ranges.append(NSRange(location: start, length: ns.length - start))
        return ranges
    }

    /// The pieces' text, each trimmed of surrounding whitespace; a piece that was only whitespace
    /// is dropped.
    public static func pieces(of text: String, maxLength: Int) -> [String] {
        let ns = text as NSString
        return cuts(in: text, maxLength: maxLength).compactMap { range in
            let piece = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return piece.isEmpty ? nil : piece
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ClauseSplitterTests`
Expected: 6 tests pass.

- [ ] **Step 5: Make the segmenter call it**

In `Sources/T2SCore/Segment/Segmenter.swift`, replace the whole private `split` method (the one beginning `/// Splits \`sentence\` into pieces ≤ maxUtteranceLength`) with:

```swift
    /// Splits `sentence` into pieces ≤ maxUtteranceLength by `ClauseSplitter`'s rule. Offsets are
    /// UTF-16 into the block. A sentence that fits is returned as it came, untouched.
    private func split(_ sentence: String, at offset: Int) -> [(String, Int)] {
        let ns = sentence as NSString
        guard ns.length > maxUtteranceLength else { return [(sentence, offset)] }
        return ClauseSplitter.cuts(in: sentence, maxLength: maxUtteranceLength).compactMap { range in
            Self.trimmed(ns.substring(with: range), at: offset + range.location)
        }
    }
```

- [ ] **Step 6: Run the segmenter suite to prove the extraction changed nothing**

Run: `swift test --filter SegmenterTests`
Expected: all 14 tests pass, including `splitsOverlongSentencesAtClauses`, `hardCutNeverSplitsASurrogatePair`, and `piecesLocateThemselvesInTheBlock`.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SCore/Segment/ClauseSplitter.swift Sources/T2SCore/Segment/Segmenter.swift Tests/T2SCoreTests/ClauseSplitterTests.swift
git commit -m "Lift the segmenter's overlong-sentence rule into ClauseSplitter so the cloud engine can share it"
```

---

### Task 2: The width contract

**Files:**
- Modify: `Sources/T2SCore/Render/SynthesisEngine.swift:35-45` (the protocol) and its extension
- Modify: `Sources/T2SCore/Render/FakeEngine.swift:4-29`
- Test: `Tests/T2SCoreTests/Render/FakeEngineTests.swift`

**Interfaces:**
- Produces: `SynthesisEngine.maxConcurrentRenders(for voiceID: String) -> Int`, default `1` via protocol extension. `FakeEngine(concurrentRenders: Int = 1)` reports that number. Tasks 3, 5, 7 depend on the method name and signature exactly.

- [ ] **Step 1: Write the failing tests**

Append to the `FakeEngineTests` suite in `Tests/T2SCoreTests/Render/FakeEngineTests.swift`:

```swift
    /// An engine that says nothing about width renders one at a time.
    @Test func theProtocolDefaultWidthIsOne() {
        struct Minimal: SynthesisEngine {
            let engineID = "minimal"
            func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
                SynthesisResult(audio: .silence(seconds: 0.1), wordTimings: [])
            }
        }
        #expect(Minimal().maxConcurrentRenders(for: "anything") == 1)
    }

    @Test func aFakeReportsTheWidthItWasBuiltWith() {
        #expect(FakeEngine().maxConcurrentRenders(for: "v") == 1)
        #expect(FakeEngine(concurrentRenders: 4).maxConcurrentRenders(for: "v") == 4)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FakeEngineTests`
Expected: compilation fails, `value of type 'Minimal' has no member 'maxConcurrentRenders'`.

- [ ] **Step 3: Add the requirement and its default**

In `Sources/T2SCore/Render/SynthesisEngine.swift`, add to the `SynthesisEngine` protocol, after `synthesizeStreaming`:

```swift
    /// How many renders the scheduler may hold in flight at once for `voiceID`'s route. Every
    /// engine that renders on the device answers 1; a hosted route answers with its mirror count.
    func maxConcurrentRenders(for voiceID: String) -> Int
```

and add to the `public extension SynthesisEngine`, after the default `synthesizeStreaming`:

```swift
    func maxConcurrentRenders(for voiceID: String) -> Int { 1 }
```

- [ ] **Step 4: Teach the fake**

In `Sources/T2SCore/Render/FakeEngine.swift`, add a stored property after `pieceCount`:

```swift
    /// What `maxConcurrentRenders(for:)` answers: the width a scheduler test wants to see.
    public let concurrentRenders: Int
```

change the initializer to:

```swift
    public init(secondsPerCharacter: TimeInterval = 0.05, simulatedRTF: Double? = nil, timeSource: ManualTimeSource? = nil,
                pieceCount: Int = 1, concurrentRenders: Int = 1) {
        self.secondsPerCharacter = secondsPerCharacter
        self.simulatedRTF = simulatedRTF
        self.timeSource = timeSource
        self.pieceCount = pieceCount
        self.concurrentRenders = concurrentRenders
    }
```

and add, after `parkedCount`:

```swift
    public nonisolated func maxConcurrentRenders(for voiceID: String) -> Int { concurrentRenders }
```

(`concurrentRenders` is a `let` of a `Sendable` type, so a `nonisolated` method may read it.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter FakeEngineTests`
Expected: all pass, the two new ones included.

- [ ] **Step 6: Run the whole root suite: nothing else may notice**

Run: `swift test`
Expected: every suite passes. Every other conformer takes the default.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SCore/Render/SynthesisEngine.swift Sources/T2SCore/Render/FakeEngine.swift Tests/T2SCoreTests/Render/FakeEngineTests.swift
git commit -m "Let an engine say how many renders it can hold in flight; every engine on the device says one"
```

---

### Task 3: The scheduler renders a batch

**Files:**
- Modify: `Sources/T2SCore/Render/RenderScheduler.swift:137-183` (`run`, `render`) and `184-253` (`renderWhileHoldingLease`)
- Test: `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift`

**Interfaces:**
- Consumes: `SynthesisEngine.maxConcurrentRenders(for:)` (Task 2), `FakeEngine(concurrentRenders:)`, `FakeEngine.parkedCount`.
- Produces: no public API change. `RenderScheduler.measuredRTF` now reflects a batch's throughput.

- [ ] **Step 1: Write the failing tests**

Add to the `RenderSchedulerTests` suite in `Tests/T2SCoreTests/Render/RenderSchedulerTests.swift`, after `aStreamThatFailsAfterAPieceStoresWhatWasHeard`:

```swift
    /// With a width of four, four requests reach the engine before any finishes, and only the
    /// batch is taken from the plan. (`setPlanFlushesPendingWork` shows the default width takes
    /// one.)
    @Test func widthFourHoldsFourRendersInFlight() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(concurrentRenders: 4)
        await engine.hold()
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan((0..<6).map { request($0, "utterance \($0)") })
        var spins = 0
        while await engine.parkedCount != 4, spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(await engine.parkedCount == 4)                            // the whole batch is in the engine
        #expect(await s.pending.count == 2)                               // and only the batch was taken
        await engine.release()
        let got = await events
        let rendered = got.compactMap { if case .rendered(let r) = $0 { return r.utteranceIndex } else { return nil } }
        #expect(rendered == [0, 1, 2, 3, 4, 5])                           // applied in submission order
    }

    /// A batch stops at a tier boundary: play-ahead and prepare never share one, so an urgent
    /// plan waits behind at most one batch of its own tier.
    @Test func aBatchNeverSpansTiers() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(concurrentRenders: 4)
        await engine.hold()
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        func req(_ i: Int, _ tier: RenderTier) -> RenderRequest {
            RenderRequest(job: RenderJob(documentID: doc, utteranceIndex: i, tier: tier), key: key(i), spoken: "x\(i)", voiceID: "v")
        }
        await s.setPlan([req(0, .playAhead), req(1, .playAhead), req(2, .prepare), req(3, .prepare)])
        var spins = 0
        while await engine.parkedCount != 2, spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(await engine.parkedCount == 2)                            // only the two play-ahead
        #expect(await s.pending.count == 2)
        await engine.release()
        _ = await events
    }

    /// Four renders that all fail to store pause the scheduler once, not four times.
    @Test func storeFullInsideABatchPausesOnce() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 100)   // nothing fits
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1, concurrentRenders: 4), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc"), request(1, "def"), request(2, "ghi"), request(3, "jkl")])
        let got = await events
        #expect(got == [.storeFull, .idle])
        #expect(await s.isPausedForStorage)
        #expect(await s.pending.isEmpty)
    }

    /// The rate control sees the batch's throughput, not one mirror's latency: four renders that
    /// each span the batch's ten seconds, for twenty seconds of audio, measure 0.5. The window is
    /// one sample so the batch's own figure is what is read — a per-render scheduler would record
    /// 2.0 for the parked render and 0 for the three that follow it unparked.
    @Test func rtfIsRecordedPerBatch() async throws {
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 1, concurrentRenders: 4)
        let s = RenderScheduler(engine: engine, store: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000), timeSource: clock, rtfWindow: 1)
        // The first sample is the warm-up's and is dropped, so spend it on a batch of one.
        async let warmUp = collect(s)
        await s.setPlan([request(9, "warm")])
        _ = await warmUp
        #expect(await s.measuredRTF == nil)

        await engine.hold()
        async let events = collect(s)
        await s.setPlan([request(0, "aaaaa"), request(1, "bbbbb"), request(2, "ccccc"), request(3, "ddddd")])   // 5 s of audio each
        var spins = 0
        while await engine.parkedCount != 4, spins < 10_000 { await Task.yield(); spins += 1 }
        clock.advance(by: 10)                                             // the whole batch took ten seconds
        await engine.release()
        _ = await events
        #expect(abs((await s.measuredRTF ?? 0) - 0.5) < 1e-9)             // 10 s / 20 s, not 10 s / 5 s
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RenderSchedulerTests`
Expected: `widthFourHoldsFourRendersInFlight` fails (`parkedCount` stays 1), `aBatchNeverSpansTiers` fails (1, not 2), `storeFullInsideABatchPausesOnce` passes by accident (width 1 also pauses once — keep it, it guards the batch path), `rtfIsRecordedPerBatch` fails (the one-sample window reads the last unparked render's 0.0). Every pre-existing test still passes.

- [ ] **Step 3: Restructure the loop around a batch**

In `Sources/T2SCore/Render/RenderScheduler.swift`, replace `run()` with:

```swift
    private func run() async {
        while !isPausedForStorage, !pending.isEmpty {
            await paceForegroundFillIfNeeded()
            guard !isPausedForStorage, !pending.isEmpty else { break }
            let batch = takeBatch()
            var paused = false
            for outcome in await render(batch) {
                switch outcome {
                case .events(let events):
                    events.forEach { continuation.yield($0) }
                case .storeFull:
                    guard !paused else { continue }               // one pause for the batch
                    paused = true
                    isPausedForStorage = true
                    pending.removeAll()
                    continuation.yield(.storeFull)
                }
            }
        }
        running = false
        continuation.yield(.idle)
    }

    /// Up to the engine's width for the first request's voice, from the front of `pending`, and
    /// never across a tier: an urgent plan then waits behind at most one batch of its own tier.
    /// On-device engines answer 1, so their batch is the single request it always was.
    private func takeBatch() -> [RenderRequest] {
        let first = pending.removeFirst()
        let width = max(1, engine.maxConcurrentRenders(for: first.voiceID))
        var batch = [first]
        while batch.count < width, let next = pending.first, next.job.tier == first.job.tier {
            batch.append(pending.removeFirst())
        }
        return batch
    }
```

Replace `render(_ request: RenderRequest)` with:

```swift
    /// The lease is held once for the batch, at the tier of its first request, and scoped to the
    /// batch's cache checks, syntheses, and store writes. Preemption between tiers happens at
    /// batch boundaries; for a width of 1 that is the utterance boundary it always was.
    private func render(_ batch: [RenderRequest]) async -> [RenderOutcome] {
        await arbiter.acquire(batch[0].job.tier)
        if isCancelled {
            await arbiter.release()
            return batch.map { _ in .events([]) }
        }
        let t0 = timeSource.now()
        let results = await renderWhileHoldingLease(batch)
        let wall = timeSource.now() - t0
        await arbiter.release()
        // Throughput, not one render's latency: the rate control asks what the route can keep
        // fed, and four mirrors that each take ten seconds deliver forty seconds of audio in ten.
        let synthesized = results.reduce(0) { $0 + $1.synthesizedSeconds }
        if synthesized > 0 { record(rtf: wall / synthesized) }
        return results.map(\.outcome)
    }

    /// Every request in the batch at once; results in the batch's order so events apply in the
    /// order the plan gave them.
    private func renderWhileHoldingLease(_ batch: [RenderRequest]) async -> [RenderResult] {
        if batch.count == 1 { return [await renderWhileHoldingLease(batch[0])] }
        return await withTaskGroup(of: (Int, RenderResult).self) { group in
            for (index, request) in batch.enumerated() {
                group.addTask { (index, await self.renderWhileHoldingLease(request)) }
            }
            var results = [RenderResult?](repeating: nil, count: batch.count)
            for await (index, result) in group { results[index] = result }
            return results.map { $0 ?? RenderResult(outcome: .events([]), synthesizedSeconds: 0) }
        }
    }
```

Then change `renderWhileHoldingLease(_ request: RenderRequest)`:

1. Its signature becomes `private func renderWhileHoldingLease(_ request: RenderRequest) async -> RenderResult`.
2. The cache-hit early return becomes `return RenderResult(outcome: .events([...same payload...]), synthesizedSeconds: 0)`.
3. Declare `var synthesized: TimeInterval = 0` beside `var events: [RenderEvent] = []`.
4. Inside the `do` block, after `let rtf: Double? = ...`, delete the line `if let rtf { record(rtf: rtf) }` and add `synthesized = result.audio.duration` — the per-render `rtf` stays, because the budget's report line still prints it.
5. Both `return .storeFull` become `return RenderResult(outcome: .storeFull, synthesizedSeconds: synthesized)`; the `return .events(events)` at the end and the one inside the write-failure `catch` become `return RenderResult(outcome: .events(events), synthesizedSeconds: synthesized)`.

Add beside `RenderOutcome` at the bottom of the actor:

```swift
    private struct RenderResult: Sendable {
        var outcome: RenderOutcome
        /// Audio seconds this render actually synthesized: 0 for a cache hit or a failure, which
        /// therefore contribute nothing to the batch's RTF.
        var synthesizedSeconds: TimeInterval
    }
```

Finally update the actor's doc comment: `/// Serial executor of \`RenderRequest\`s` becomes `/// Executor of \`RenderRequest\`s, one batch at a time — a batch as wide as the engine allows, one for anything on the device`.

- [ ] **Step 4: Run the scheduler tests to verify they pass**

Run: `swift test --filter RenderSchedulerTests`
Expected: every test passes, the four new ones and all pre-existing ones (`measuresRollingRTF`, `firstSampleIsNotRecorded`, the pacing suite) unchanged.

Notes for the implementer: a batch member that is the streaming head still yields `.piece` events straight to the continuation from inside `streamed`; that path is untouched. `foregroundFillDelay` is set per render and the last one in a batch wins; the cloud route has no fill rate and the on-device route has width 1, so the two never meet. `budget?.waitForHeadroom` is called by each member; cloud renders cost no CPU, so it returns at once after the first.

- [ ] **Step 5: Run the whole root suite**

Run: `swift test`
Expected: every suite passes, `PlaybackCoordinatorTests` included.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SCore/Render/RenderScheduler.swift Tests/T2SCoreTests/Render/RenderSchedulerTests.swift
git commit -m "The scheduler renders a batch as wide as the engine allows, never across a tier, and measures the batch's throughput"
```

---

### Task 4: A route with mirrors

**Files:**
- Modify: `Sources/T2SAudio/HTTPVoiceEngine.swift:7-63` (`HTTPVoiceConfiguration`)
- Test: `Tests/T2SAudioTests/HTTPVoiceEngineTests.swift`

**Interfaces:**
- Produces: `HTTPVoiceConfiguration.endpoints: [URL]` (never empty), `init(endpoints:model:voice:requestRatePerMinute:)`, the existing `init(endpoint:...)` kept, `endpoint: URL` as a computed alias for `endpoints[0]`. `fingerprint` covers the primary only. `validate()` checks every endpoint and rejects duplicates. Tasks 5, 7, 8 depend on `endpoints`.

- [ ] **Step 1: Write the failing tests**

Add to the `HTTPVoiceEngineTests` suite, after `rejectsAnEndpointThatCouldPersistAKeyInItsURL`:

```swift
    /// Mirrors serve the same audio, so adding one keeps cached renders; changing the primary is
    /// a new route, as it always was.
    @Test func mirrorsDoNotChangeTheRouteIdentityButThePrimaryDoes() throws {
        let primary = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let mirror = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let alone = HTTPVoiceConfiguration(endpoint: primary, model: "m", voice: "v", requestRatePerMinute: 60)
        let mirrored = HTTPVoiceConfiguration(endpoints: [primary, mirror], model: "m", voice: "v", requestRatePerMinute: 60)
        let swapped = HTTPVoiceConfiguration(endpoints: [mirror, primary], model: "m", voice: "v", requestRatePerMinute: 60)

        #expect(mirrored.fingerprint == alone.fingerprint)
        #expect(swapped.fingerprint != alone.fingerprint)
        #expect(mirrored.endpoint == primary)
    }

    @Test func everyMirrorMustPassTheEndpointRulesAndBeDistinct() throws {
        let good = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let plain = try #require(URL(string: "http://two.example/v1/audio/speech"))
        let leaky = try #require(URL(string: "https://two.example/v1/audio/speech?key=x"))
        for bad in [plain, leaky] {
            let configuration = HTTPVoiceConfiguration(endpoints: [good, bad], model: "m", voice: "v", requestRatePerMinute: 60)
            #expect(throws: HTTPVoiceError.invalidConfiguration) { try configuration.validate() }
        }
        let duplicated = HTTPVoiceConfiguration(endpoints: [good, good], model: "m", voice: "v", requestRatePerMinute: 60)
        #expect(throws: HTTPVoiceError.invalidConfiguration) { try duplicated.validate() }
        let other = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let fine = HTTPVoiceConfiguration(endpoints: [good, other], model: "m", voice: "v", requestRatePerMinute: 60)
        #expect(throws: Never.self) { try fine.validate() }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HTTPVoiceEngineTests`
Expected: compilation fails, `extra argument 'endpoints' in call`.

- [ ] **Step 3: Give the configuration its mirrors**

In `Sources/T2SAudio/HTTPVoiceEngine.swift`, replace the body of `HTTPVoiceConfiguration` from `public let endpoint: URL` through the end of `canonicalEndpoint` with:

```swift
    /// The primary first, then its mirrors: identical deployments that serve the same audio for
    /// the same request. Never empty.
    public let endpoints: [URL]
    public let model: String
    public let voice: String
    /// Applies to each endpoint separately.
    public let requestRatePerMinute: Int

    public init(endpoints: [URL], model: String, voice: String, requestRatePerMinute: Int) {
        precondition(!endpoints.isEmpty, "a cloud route needs at least one endpoint")
        self.endpoints = endpoints
        self.model = model.trimmed
        self.voice = voice.trimmed
        self.requestRatePerMinute = requestRatePerMinute
    }

    public init(endpoint: URL, model: String, voice: String, requestRatePerMinute: Int) {
        self.init(endpoints: [endpoint], model: model, voice: voice, requestRatePerMinute: requestRatePerMinute)
    }

    /// The primary. Its identity is the route's; a mirror is interchangeable with it.
    public var endpoint: URL { endpoints[0] }

    /// A non-secret identity for rendered audio. Rate limiting is intentionally excluded: changing
    /// it does not change a provider's PCM output, while endpoint/model/voice/format do. Mirrors
    /// are excluded for the same reason: they serve the primary's output.
    public var fingerprint: String {
        let material = [Self.formatVersion, Self.canonical(endpoint), model.trimmed, voice.trimmed].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func validate() throws {
        guard !model.isEmpty, !voice.isEmpty, (1...120).contains(requestRatePerMinute) else { throw HTTPVoiceError.invalidConfiguration }
        for endpoint in endpoints { try Self.validate(endpoint: endpoint) }
        guard Set(endpoints.map(Self.canonical)).count == endpoints.count else { throw HTTPVoiceError.invalidConfiguration }
    }

    private static func validate(endpoint: URL) throws {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { throw HTTPVoiceError.invalidConfiguration }
    }

    private static func canonical(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
```

Leave `formatVersion` and `example` as they are.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HTTPVoiceEngineTests`
Expected: all pass, the two new ones included.

- [ ] **Step 5: Run the whole root suite**

Run: `swift test`
Expected: every suite passes — `RoutedEngineTests`, `CloudVoiceSettingsTests`, and `PlaybackCoordinatorTests` all build configurations with `endpoint:` and are unaffected.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SAudio/HTTPVoiceEngine.swift Tests/T2SAudioTests/HTTPVoiceEngineTests.swift
git commit -m "A cloud route names its mirrors; the primary alone carries the route's identity"
```

---

### Task 5: The engine spreads requests across mirrors

**Files:**
- Modify: `Sources/T2SAudio/HTTPVoiceEngine.swift` (the `HTTPVoiceEngine` class)
- Test: `Tests/T2SAudioTests/HTTPVoiceEngineTests.swift` (`TestURLProtocol` and new tests)

**Interfaces:**
- Consumes: `HTTPVoiceConfiguration.endpoints` (Task 4), `RequestRateLimiter(requestsPerMinute:now:sleeper:)`.
- Produces: `HTTPVoiceEngine.init(configuration:key:session:limiterSleeper:)` — the old unused `limiter:` parameter is gone. `maxConcurrentRenders(for:)` returns the endpoint count. `TestURLProtocol.Response`, `TestURLProtocol.session(byHost:fallback:)`, `TestURLProtocol.session(answering:)`, `TestURLProtocol.allRequests`, `TestURLProtocol.pcmResponse(samples:)` for Tasks 6 and 7.

- [ ] **Step 1: Extend the test transport**

In `Tests/T2SAudioTests/HTTPVoiceEngineTests.swift`, replace the whole `TestURLProtocol` class with:

```swift
final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int
        var headers: [String: String]
        var data: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response(status: 500, headers: [:], data: Data())
    /// Answers by host when set; a host with no entry gets `response`.
    nonisolated(unsafe) private static var responsesByHost: [String: Response] = [:]
    /// Answers from the request itself when set; wins over the host table.
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> Response)?
    nonisolated(unsafe) private static var capturedRequest: URLRequest?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    /// Every request since the session was made, in arrival order.
    static var allRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func session(status: Int, headers: [String: String] = [:], json: String) -> URLSession {
        session(status: status, headers: headers, body: Data(json.utf8))
    }

    static func session(status: Int, headers: [String: String] = [:], body: Data) -> URLSession {
        session(byHost: [:], fallback: Response(status: status, headers: headers, data: body))
    }

    /// One answer per host; `fallback` answers any host not listed.
    static func session(byHost: [String: Response], fallback: Response = Response(status: 500, headers: [:], data: Data())) -> URLSession {
        reset(response: fallback, byHost: byHost, responder: nil)
        return make()
    }

    /// An answer computed from each request, for tests that need to tell pieces apart by body.
    static func session(answering responder: @escaping @Sendable (URLRequest) -> Response) -> URLSession {
        reset(response: Response(status: 500, headers: [:], data: Data()), byHost: [:], responder: responder)
        return make()
    }

    /// Raw 16-bit little-endian PCM at 24 kHz, the pilot server's answer.
    static func pcmResponse(samples: [Int16], status: Int = 200) -> Response {
        var data = Data()
        for value in samples { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return Response(status: status, headers: ["Content-Type": "audio/pcm"], data: data)
    }

    private static func reset(response: Response, byHost: [String: Response], responder: (@Sendable (URLRequest) -> Response)?) {
        lock.lock()
        self.response = response
        responsesByHost = byHost
        self.responder = responder
        capturedRequest = nil
        capturedRequests = []
        lock.unlock()
    }

    private static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        var captured = request
        if captured.httpBody == nil {
            captured.httpBody = Self.readBody(from: captured.httpBodyStream)
        }
        Self.capturedRequest = captured
        Self.capturedRequests.append(captured)
        let response = Self.responder?(captured)
            ?? captured.url?.host.flatMap { Self.responsesByHost[$0] }
            ?? Self.response
        Self.lock.unlock()

        let urlResponse = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil,
                                          headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
```

`readBody` is the original, verbatim; only the capture and lookup logic changed.

- [ ] **Step 2: Write the failing tests**

Add to the `HTTPVoiceEngineTests` suite, before `rateLimiterSpacesRequestsAndHonoursRetryAfter`:

```swift
    /// Four concurrent calls land one on each mirror: the engine's width is its mirror count and
    /// a batch that wide never queues behind itself.
    @Test func spreadsConcurrentRequestsOneToEachMirror() async throws {
        let hosts = ["one.example", "two.example", "three.example", "four.example"]
        let pcm = TestURLProtocol.pcmResponse(samples: [1])
        let session = TestURLProtocol.session(byHost: Dictionary(uniqueKeysWithValues: hosts.map { ($0, pcm) }))
        let configuration = HTTPVoiceConfiguration(
            endpoints: try hosts.map { try #require(URL(string: "https://\($0)/v1/audio/speech")) },
            model: "m", voice: "v", requestRatePerMinute: 60)
        let engine = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: session, limiterSleeper: { _ in })

        #expect(engine.maxConcurrentRenders(for: "cloud:x:v") == 4)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<4 {
                group.addTask { _ = try await engine.synthesize(.init(spoken: "piece \(i)", voiceID: "cloud:x:v")) }
            }
            try await group.waitForAll()
        }
        #expect(Set(TestURLProtocol.allRequests.compactMap { $0.url?.host }) == Set(hosts))
    }

    /// A busy mirror answers 429; the request walks to the next mirror and fails only when every
    /// mirror has refused it, each tried once.
    @Test func aBusyMirrorHandsTheRequestToTheNext() async throws {
        let busy = TestURLProtocol.Response(status: 429, headers: ["Retry-After": "2"], data: Data("{\"detail\":\"Synthesis busy\"}".utf8))
        let fine = TestURLProtocol.pcmResponse(samples: [7])
        let one = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let two = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let configuration = HTTPVoiceConfiguration(endpoints: [one, two], model: "m", voice: "v", requestRatePerMinute: 60)

        let session = TestURLProtocol.session(byHost: ["one.example": busy, "two.example": fine])
        let engine = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: session, limiterSleeper: { _ in })
        let result = try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:x:v"))
        #expect(result.audio.samples.count == 1)
        #expect(TestURLProtocol.allRequests.compactMap { $0.url?.host } == ["one.example", "two.example"])

        let allBusy = TestURLProtocol.session(byHost: ["one.example": busy, "two.example": busy])
        let refused = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: allBusy, limiterSleeper: { _ in })
        await #expect(throws: HTTPVoiceError.rateLimited(retryAfter: 2)) {
            try await refused.synthesize(.init(spoken: "x", voiceID: "cloud:x:v"))
        }
        #expect(TestURLProtocol.allRequests.count == 2)
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter HTTPVoiceEngineTests`
Expected: compilation fails, `extra argument 'limiterSleeper' in call`.

- [ ] **Step 4: Rebuild the engine around routes**

In `Sources/T2SAudio/HTTPVoiceEngine.swift`, replace the `HTTPVoiceEngine` class from its declaration through the end of `synthesize` (leave `maximumResponseBytes`, `isJSON`, `sixteenBitSamples`, `safeServerMessage`, `timings` and the wire types as they are) with:

```swift
public final class HTTPVoiceEngine: SynthesisEngine, @unchecked Sendable {
    public let engineID = "http-voice-v2"

    private let configuration: HTTPVoiceConfiguration
    private let key: @Sendable () async throws -> String?
    private let session: URLSession
    /// One per endpoint, in the configuration's order: each mirror is rate-limited on its own.
    private let routes: [Route]
    private let cursor = Cursor()

    private struct Route: Sendable {
        let endpoint: URL
        let limiter: RequestRateLimiter
    }

    /// Round-robin over the routes. Each request takes the next, so a batch as wide as the mirror
    /// list lands one request on each mirror.
    private final class Cursor: @unchecked Sendable {
        private let lock = NSLock()
        private var next = 0

        func take(of count: Int) -> Int {
            lock.lock()
            defer { lock.unlock() }
            let index = next % count
            next = (next + 1) % count
            return index
        }
    }

    /// `limiterSleeper` replaces every route's limiter sleep — a test's no-op, so pieces sent at
    /// once to one endpoint do not wait a real second apart.
    public init(configuration: HTTPVoiceConfiguration, key: @escaping @Sendable () async throws -> String?,
                session: URLSession = .shared, limiterSleeper: RequestRateLimiter.Sleeper? = nil) {
        self.configuration = configuration
        self.key = key
        self.session = session
        routes = configuration.endpoints.map { endpoint in
            let limiter = limiterSleeper.map { RequestRateLimiter(requestsPerMinute: configuration.requestRatePerMinute, sleeper: $0) }
                ?? RequestRateLimiter(requestsPerMinute: configuration.requestRatePerMinute)
            return Route(endpoint: endpoint, limiter: limiter)
        }
    }

    public func maxConcurrentRenders(for voiceID: String) -> Int { routes.count }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try configuration.validate()
        let providerVoice = CloudVoiceID(rawValue: request.voiceID)?.voice ?? configuration.voice
        return try await synthesizePiece(request.spoken, voice: providerVoice)
    }

    /// One request, on the next mirror. A mirror that answers 429 has its limiter deferred and the
    /// request walks on; each mirror is tried at most once, and only when all have refused does
    /// the request fail as rate limited.
    private func synthesizePiece(_ text: String, voice: String) async throws -> SynthesisResult {
        guard let key = try await key()?.trimmed, !key.isEmpty else { throw HTTPVoiceError.missingKey }
        let start = cursor.take(of: routes.count)
        var refused: HTTPVoiceError?
        for attempt in 0 ..< routes.count {
            let route = routes[(start + attempt) % routes.count]
            await route.limiter.wait()
            do {
                return try await post(text: text, voice: voice, key: key, to: route.endpoint)
            } catch HTTPVoiceError.rateLimited(let retryAfter) {
                await route.limiter.deferUntil(seconds: retryAfter)
                refused = .rateLimited(retryAfter: retryAfter)
            }
        }
        throw refused ?? HTTPVoiceError.transport("no mirror answered")
    }

    private func post(text: String, voice: String, key: String, to endpoint: URL) async throws -> SynthesisResult {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(WireRequest(
            model: configuration.model,
            input: text,
            voice: voice,
            responseFormat: "pcm"
        ))

        do {
            var data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                throw HTTPVoiceError.transport("request failed")
            }
            defer { data.removeAll(keepingCapacity: false) }

            guard let http = response as? HTTPURLResponse else {
                throw HTTPVoiceError.transport("no HTTP response")
            }
            if http.statusCode == 429 {
                throw HTTPVoiceError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
            }
            guard (200...299).contains(http.statusCode) else {
                throw HTTPVoiceError.server(status: http.statusCode, message: Self.safeServerMessage(status: http.statusCode))
            }
            guard data.count <= Self.maximumResponseBytes else { throw HTTPVoiceError.malformedResponse }

            guard Self.isJSON(http, data) else {
                // OpenAI's `pcm`: 16-bit little-endian mono at 24 kHz, no timings.
                let samples = try Self.sixteenBitSamples(data)
                return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: samples), wordTimings: [])
            }

            let wire: WireResponse
            do {
                wire = try JSONDecoder().decode(WireResponse.self, from: data)
            } catch {
                throw HTTPVoiceError.malformedResponse
            }
            guard wire.sampleRate == 24_000,
                  let bytes = Data(base64Encoded: wire.audio),
                  bytes.count <= Self.maximumResponseBytes,
                  bytes.count.isMultiple(of: MemoryLayout<UInt32>.size)
            else { throw HTTPVoiceError.malformedResponse }

            let samples: [Float] = stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map { offset in
                let bits: UInt32 = bytes.withUnsafeBytes { pointer in
                    pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                }
                return Float(bitPattern: UInt32(littleEndian: bits))
            }
            guard samples.allSatisfy(\.isFinite) else { throw HTTPVoiceError.malformedResponse }
            let duration = Double(samples.count) / 24_000
            return SynthesisResult(
                audio: PCMAudio(sampleRate: 24_000, samples: samples),
                wordTimings: try Self.timings(wire.wordTimings, text: text, duration: duration)
            )
        } catch let error as HTTPVoiceError {
            throw error
        } catch {
            throw HTTPVoiceError.transport("request failed")
        }
    }
```

The engine's existing doc comment above the class stays. `RequestRateLimiter` already exposes `Sleeper` and takes `sleeper:`; nothing there changes.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter HTTPVoiceEngineTests`
Expected: all pass. `statusAndMissingKeySurfaceActionableErrors` still sees `rateLimited(retryAfter: 12)` from a single endpoint: one route, tried once.

- [ ] **Step 6: Run the whole root suite**

Run: `swift test`
Expected: every suite passes. (`RoutedEngine` constructs the engine without `limiterSleeper`, so it takes the real sleeper.)

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SAudio/HTTPVoiceEngine.swift Tests/T2SAudioTests/HTTPVoiceEngineTests.swift
git commit -m "The HTTP engine spreads requests across its mirrors and walks a request past a busy one"
```

---

### Task 6: Long utterances stay under Eco's ceiling

**Files:**
- Modify: `Sources/T2SAudio/HTTPVoiceEngine.swift` (`synthesize` and a constant)
- Test: `Tests/T2SAudioTests/HTTPVoiceEngineTests.swift`

**Interfaces:**
- Consumes: `ClauseSplitter.pieces(of:maxLength:)` (Task 1), `synthesizePiece(_:voice:)` (Task 5), `TestURLProtocol.session(answering:)` (Task 5).
- Produces: `HTTPVoiceEngine.maxRequestCharacters` (`static let`, internal, `180`).

- [ ] **Step 1: Write the failing test**

Add to the `HTTPVoiceEngineTests` suite, after `aBusyMirrorHandsTheRequestToTheNext`:

```swift
    /// Text over the request cap is cut at clause boundaries, the pieces sent at once, and their
    /// audio joined in text order whichever mirror answers first.
    @Test func longTextIsSplitAtClausesSentConcurrentlyAndJoinedInOrder() async throws {
        // Three clauses of 170 characters: each fits the 180 cap alone, the whole does not.
        let clauses = (1...3).map { n in "\(n) " + String(repeating: "w", count: 166) + "," }
        let text = clauses.joined(separator: " ")
        // Answer each piece with one sample carrying its leading digit, so the join order shows.
        let session = TestURLProtocol.session { request in
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let input = body?["input"] as? String ?? "0"
            return TestURLProtocol.pcmResponse(samples: [Int16(String(input.prefix(1))) ?? 0])
        }
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session, limiterSleeper: { _ in })

        let result = try await engine.synthesize(.init(spoken: text, voiceID: "cloud:x:v"))

        let sent = TestURLProtocol.allRequests.compactMap { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])?["input"] as? String
        }
        #expect(sent.count == 3)
        #expect(Set(sent) == Set(clauses))
        #expect(sent.allSatisfy { ($0 as NSString).length <= HTTPVoiceEngine.maxRequestCharacters })
        #expect(result.audio.samples.map { Int16(($0 * 32768).rounded()) } == [1, 2, 3])
        #expect(result.wordTimings.isEmpty)
    }

    /// Text within the cap goes out exactly as it came, untouched by the splitter.
    @Test func shortTextIsSentWhole() async throws {
        let session = TestURLProtocol.session(status: 200, headers: ["Content-Type": "audio/pcm"], body: Data([0, 0]))
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session, limiterSleeper: { _ in })
        _ = try await engine.synthesize(.init(spoken: "  Kept, spaces and all.  ", voiceID: "cloud:x:v"))
        let body = try #require(TestURLProtocol.lastRequest?.httpBody)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(request?["input"] as? String == "  Kept, spaces and all.  ")
        #expect(TestURLProtocol.allRequests.count == 1)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter HTTPVoiceEngineTests`
Expected: compilation fails, `type 'HTTPVoiceEngine' has no member 'maxRequestCharacters'`.

- [ ] **Step 3: Split, send, join**

In `Sources/T2SAudio/HTTPVoiceEngine.swift`, add after `public let engineID = "http-voice-v2"`:

```swift
    /// The longest text sent in one request. Eco's 30 s router timeout was measured at about 210
    /// characters (`docs/superpowers/evidence/2026-09-11-heroku-eco-measurements.log`); anything
    /// longer is cut at clause boundaries and the pieces sent at once.
    static let maxRequestCharacters = 180
```

and replace `synthesize` with:

```swift
    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try configuration.validate()
        let providerVoice = CloudVoiceID(rawValue: request.voiceID)?.voice ?? configuration.voice
        let pieces = ClauseSplitter.pieces(of: request.spoken, maxLength: Self.maxRequestCharacters)
        guard pieces.count > 1 else {
            return try await synthesizePiece(request.spoken, voice: providerVoice)
        }
        let results = try await withThrowingTaskGroup(of: (Int, SynthesisResult).self) { group in
            for (index, piece) in pieces.enumerated() {
                group.addTask { (index, try await self.synthesizePiece(piece, voice: providerVoice)) }
            }
            var ordered = [SynthesisResult?](repeating: nil, count: pieces.count)
            for try await (index, result) in group { ordered[index] = result }
            return ordered.compactMap { $0 }
        }
        // Pieces rendered apart carry no timings over the whole; the pilot server sends none anyway.
        return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: results.flatMap(\.audio.samples)), wordTimings: [])
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HTTPVoiceEngineTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/HTTPVoiceEngine.swift Tests/T2SAudioTests/HTTPVoiceEngineTests.swift
git commit -m "An utterance longer than a hosted request may carry is cut at clauses and its pieces sent at once"
```

---

### Task 7: The router forwards the width

**Files:**
- Modify: `Sources/T2SAudio/RoutedEngine.swift:79-93` (the cloud branch of `engine(for:)`) and a new method
- Test: `Tests/T2SAudioTests/RoutedEngineTests.swift`

**Interfaces:**
- Consumes: `HTTPVoiceConfiguration.endpoints`, `CloudVoiceID(rawValue:)`, `TestURLProtocol.session(byHost:)` and `pcmResponse(samples:)` (Task 5).
- Produces: `RoutedEngine.maxConcurrentRenders(for:)` — `nonisolated`, the endpoint count for a cloud voice whose fingerprint matches the current configuration, else 1.

- [ ] **Step 1: Write the failing tests**

Add to the `RoutedEngineTests` suite, after `refusesAKokoroIdentityFromAnotherBuildAndOneWithNoKokoroEngine`:

```swift
    @Test func reportsTheMirrorCountForACloudVoiceAndOneForEverythingElse() throws {
        let configuration = HTTPVoiceConfiguration(
            endpoints: [
                try #require(URL(string: "https://one.example/v1/audio/speech")),
                try #require(URL(string: "https://two.example/v1/audio/speech")),
                try #require(URL(string: "https://three.example/v1/audio/speech")),
            ],
            model: "m", voice: "v", requestRatePerMinute: 60)
        let routed = RoutedEngine(system: RecordingEngine(), configuration: { configuration }, key: { nil })
        let cloud = CloudVoiceID(configuration: configuration, voice: "v").rawValue

        #expect(routed.maxConcurrentRenders(for: cloud) == 3)
        #expect(routed.maxConcurrentRenders(for: "cloud:stale:v") == 1)
        #expect(routed.maxConcurrentRenders(for: "system:com.example.voice") == 1)
        #expect(routed.maxConcurrentRenders(for: KokoroVoiceID(engineID: "kokoro-x", voice: "af_heart").rawValue) == 1)
    }

    /// The fingerprint ignores mirrors, so the engine cache cannot key on it alone: a changed
    /// mirror list builds a new engine, seen here as the new mirror taking its turn.
    @Test func aChangedMirrorListRebuildsTheCloudEngine() async throws {
        let one = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let two = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let pcm = TestURLProtocol.pcmResponse(samples: [1])
        let session = TestURLProtocol.session(byHost: ["one.example": pcm, "two.example": pcm])
        let box = ConfigurationBox(HTTPVoiceConfiguration(endpoints: [one], model: "m", voice: "v", requestRatePerMinute: 120))
        let routed = RoutedEngine(system: RecordingEngine(), configuration: { box.value }, key: { "test-key" }, session: session)
        let voiceID = CloudVoiceID(configuration: try #require(box.value), voice: "v").rawValue

        _ = try await routed.synthesize(.init(spoken: "a", voiceID: voiceID))
        box.value = HTTPVoiceConfiguration(endpoints: [one, two], model: "m", voice: "v", requestRatePerMinute: 120)
        _ = try await routed.synthesize(.init(spoken: "b", voiceID: voiceID))      // same fingerprint, new engine: its cursor starts at one
        _ = try await routed.synthesize(.init(spoken: "c", voiceID: voiceID))      // then two

        #expect(TestURLProtocol.allRequests.compactMap { $0.url?.host } == ["one.example", "one.example", "two.example"])
    }
```

and at the bottom of the file, beside `RecordingEngine`:

```swift
private final class ConfigurationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HTTPVoiceConfiguration?
    init(_ value: HTTPVoiceConfiguration?) { stored = value }
    var value: HTTPVoiceConfiguration? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RoutedEngineTests`
Expected: `reportsTheMirrorCountForACloudVoiceAndOneForEverythingElse` fails (the protocol default answers 1 for the cloud voice); `aChangedMirrorListRebuildsTheCloudEngine` fails (`["one.example", "one.example", "one.example"]`: the cached engine never learned of the mirror).

- [ ] **Step 3: Forward the width and widen the cache key**

In `Sources/T2SAudio/RoutedEngine.swift`, add after `synthesizeStreaming`:

```swift
    /// A cloud voice renders as wide as its mirror list; everything on the device renders one at
    /// a time. Reads only the configuration closure, so it needs no actor hop.
    public nonisolated func maxConcurrentRenders(for voiceID: String) -> Int {
        guard let cloudID = CloudVoiceID(rawValue: voiceID),
              let configuration = configuration(),
              configuration.fingerprint == cloudID.fingerprint
        else { return 1 }
        return max(1, configuration.endpoints.count)
    }
```

and in `engine(for:)`, replace the `cacheKey` line with:

```swift
            // The fingerprint ignores mirrors on purpose (cached audio survives a mirror edit), so
            // the engine, which must know every mirror, is keyed on all of them.
            let cacheKey = ([configuration.fingerprint, String(configuration.requestRatePerMinute)]
                            + configuration.endpoints.map(\.absoluteString)).joined(separator: "\u{1F}")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RoutedEngineTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/RoutedEngine.swift Tests/T2SAudioTests/RoutedEngineTests.swift
git commit -m "The router answers a cloud voice's width and rebuilds the engine when its mirrors change"
```

---

### Task 8: One endpoint per line in Cloud voices

**Files:**
- Modify: `Sources/T2SApp/Preferences/CloudVoiceSettings.swift:142-149` (`makeConfiguration`)
- Modify: `App/T2SReader/Preferences/CloudVoicesPage.swift:23` (caption), `:31` (endpoint field), `:106` (`field` helper)
- Test: `Tests/T2SAppTests/CloudVoiceSettingsTests.swift`

**Interfaces:**
- Consumes: `HTTPVoiceConfiguration(endpoints:...)` (Task 4).
- Produces: nothing new in API; `endpointText` is now one URL per line, first the primary, blank lines ignored.

- [ ] **Step 1: Write the failing tests**

Add to the `CloudVoiceSettingsTests` suite, after `invalidValuesCannotEnableTheCloudRoute`:

```swift
    @Test func oneEndpointPerLineTheFirstBeingThePrimary() async throws {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = " https://one.example/v1/audio/speech \n\nhttps://two.example/v1/audio/speech\nhttps://three.example/v1/audio/speech\n"
        settings.model = "m"
        settings.voice = "v"
        try await settings.save()

        let configuration = try #require(settings.configurationStore.current())
        #expect(configuration.endpoints.map(\.host) == ["one.example", "two.example", "three.example"])
        #expect(configuration.endpoint.host == "one.example")
    }

    /// Adding a mirror keeps the route's identity, so nothing already rendered is thrown away.
    @Test func aMirrorEditKeepsTheRouteIdentity() throws {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = "https://one.example/v1/audio/speech"
        settings.model = "m"
        settings.voice = "v"
        let alone = try #require(settings.cloudVoiceID)
        settings.endpointText += "\nhttps://two.example/v1/audio/speech"
        #expect(settings.cloudVoiceID == alone)
    }

    @Test func aBadMirrorLineInvalidatesTheRoute() async {
        let settings = CloudVoiceSettings(defaults: freshDefaults())
        settings.endpointText = "https://one.example/v1/audio/speech\nhttp://two.example/v1/audio/speech"
        settings.model = "m"
        settings.voice = "v"
        await #expect(throws: HTTPVoiceError.invalidConfiguration) { try await settings.save() }
        #expect(settings.cloudVoiceID == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CloudVoiceSettingsTests`
Expected: `oneEndpointPerLineTheFirstBeingThePrimary` and `aMirrorEditKeepsTheRouteIdentity` fail with `invalidConfiguration` (a newline is not a URL); `aBadMirrorLineInvalidatesTheRoute` passes by accident and stays as the guard.

- [ ] **Step 3: Parse lines**

In `Sources/T2SApp/Preferences/CloudVoiceSettings.swift`, replace `makeConfiguration` with:

```swift
    /// One endpoint per line, the first being the primary; blank lines are ignored. A single line
    /// is what every existing install has stored, and it parses as before.
    private static func makeConfiguration(endpointText: String, model: String, voice: String, rate: Int) throws -> HTTPVoiceConfiguration {
        let endpoints = try endpointText.split(whereSeparator: \.isNewline).compactMap { line -> URL? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            guard let url = URL(string: trimmed) else { throw HTTPVoiceError.invalidConfiguration }
            return url
        }
        guard !endpoints.isEmpty else { throw HTTPVoiceError.invalidConfiguration }
        let configuration = HTTPVoiceConfiguration(endpoints: endpoints, model: model, voice: voice, requestRatePerMinute: rate)
        try configuration.validate()
        return configuration
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CloudVoiceSettingsTests`
Expected: all pass, the two pre-existing tests included.

- [ ] **Step 5: Let the screen take several lines**

In `App/T2SReader/Preferences/CloudVoicesPage.swift`:

Change the `field` helper's signature and first line to:

```swift
    private func field(_ title: String, text: Binding<String>, contentType: UITextContentType? = nil, axis: Axis = .horizontal) -> some View {
        TextField(title, text: text, axis: axis)
            .lineLimit(axis == .vertical ? 4 : nil)
```

leaving every modifier that follows as it is.

Change the endpoint field call to:

```swift
                    field("HTTPS endpoint, one per line", text: $settings.endpointText, contentType: .URL, axis: .vertical)
```

Append one sentence to the "Provider contract" caption `Text`, inside the same string literal after `...JSON that adds word timings.`:

```
 More than one endpoint, one per line, are identical mirrors of the first; the app spreads requests across them.
```

- [ ] **Step 6: Build the app target**

The project's app schemes are `Simulator` (the everyday `T2SReader` target) and `Phone` (the `T2SReaderKokoro` build); the settings page is in both. Build the everyday one:

Run: `xcodebuild -project App/T2SReader.xcodeproj -scheme Simulator -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SApp/Preferences/CloudVoiceSettings.swift App/T2SReader/Preferences/CloudVoicesPage.swift Tests/T2SAppTests/CloudVoiceSettingsTests.swift
git commit -m "Cloud voices takes one endpoint per line; the first is the route, the rest are its mirrors"
```

---

### Task 9: The server's 422 stops echoing the request

**Files:**
- Modify: `Server/HerokuVoice/voice_service/web.py` (imports, `create_app`)
- Test: `Server/HerokuVoice/tests/test_web.py`

**Interfaces:**
- Produces: every `RequestValidationError` answers `{"detail": "Invalid request"}`. The `InputExpansionError` 422 keeps its own detail; it is an `HTTPException`, not a validation error.

- [ ] **Step 1: Write the failing test**

Append to `Server/HerokuVoice/tests/test_web.py`:

```python
def test_speech_validation_errors_never_echo_the_request() -> None:
    client, engine = make_client()
    body = valid_request()
    body["input"] = "x" * 401

    response = client.post(
        "/v1/audio/speech",
        headers={"Authorization": "Bearer pilot-secret"},
        json=body,
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "Invalid request"}
    assert "xxxx" not in response.text
    assert engine.calls == []
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd Server/HerokuVoice && PYTHONPATH=. /tmp/t2s-heroku-voice-venv/bin/python -m pytest tests/test_web.py -q -k never_echo`
Expected: FAIL — the default body is a list carrying the 401-character input.

- [ ] **Step 3: Answer without the request**

In `Server/HerokuVoice/voice_service/web.py`, change the FastAPI import line to:

```python
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.exceptions import RequestValidationError
```

and inside `create_app`, directly after `app.add_middleware(SpeechRequestGuard, api_key=api_key)`, add:

```python
    @app.exception_handler(RequestValidationError)
    async def reject_without_echo(_request: Request, _error: RequestValidationError) -> JSONResponse:
        # FastAPI's default body repeats the offending input. Nothing a client sent comes back.
        return JSONResponse(
            {"detail": "Invalid request"},
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        )
```

- [ ] **Step 4: Run the server suite**

Run: `cd Server/HerokuVoice && PYTHONPATH=. /tmp/t2s-heroku-voice-venv/bin/python -m pytest tests -q`
Expected: 36 passed (35 before plus this one).

- [ ] **Step 5: Commit**

```bash
git add Server/HerokuVoice/voice_service/web.py Server/HerokuVoice/tests/test_web.py
git commit -m "A rejected request body is answered without repeating it"
```

---

### Task 10: Deploy the mirrors

**Files:**
- Create: `Server/HerokuVoice/scripts/mirrors.sh`
- Modify: `Server/HerokuVoice/README.md` (a "Mirrors" section)

**Interfaces:**
- Consumes: the committed `Server/HerokuVoice` subtree (Task 9 committed), the Heroku CLI logged in as the app owner, the bearer key.
- Produces: apps `kokoro-t2s`, `kokoro-t2s-m2`, `kokoro-t2s-m3`, `kokoro-t2s-m4`, each `web=1:eco`, one build, one key; the four `/v1/audio/speech` URLs for Task 11.

- [ ] **Step 1: Put the key somewhere that survives a reboot**

The pilot's key was written to `/tmp/t2s-voice-key`, which macOS clears. Move it, or if it is already gone, read it back from the primary app without printing it:

```bash
mkdir -p ~/.t2s && chmod 700 ~/.t2s
if [ -f /tmp/t2s-voice-key ]; then
  mv /tmp/t2s-voice-key ~/.t2s/heroku-voice-key
else
  heroku config:get T2S_VOICE_API_KEY -a kokoro-t2s > ~/.t2s/heroku-voice-key
fi
chmod 600 ~/.t2s/heroku-voice-key
wc -c < ~/.t2s/heroku-voice-key      # a length, never the key: expect 44
```

- [ ] **Step 2: Write the script**

Create `Server/HerokuVoice/scripts/mirrors.sh` (then `chmod +x` it):

```bash
#!/usr/bin/env bash
# Deploys Server/HerokuVoice to N identical Heroku Eco apps and verifies each one.
# Safe to re-run: every step is idempotent. Eco only, by construction.
#
#   scripts/mirrors.sh [count]        default 4
#
# The bearer key is read from $T2S_VOICE_KEY_FILE (default ~/.t2s/heroku-voice-key),
# which must be mode 0600. It is never printed.
set -euo pipefail

COUNT="${1:-4}"
PRIMARY="kokoro-t2s"
KEY_FILE="${T2S_VOICE_KEY_FILE:-$HOME/.t2s/heroku-voice-key}"
SIZE="eco"                                    # the only size this script will ever scale to

case "$COUNT" in ''|*[!0-9]*) echo "count must be a positive integer" >&2; exit 2;; esac
[ "$COUNT" -ge 1 ] || { echo "count must be at least 1" >&2; exit 2; }
[ -f "$KEY_FILE" ] || { echo "no key file at $KEY_FILE" >&2; exit 2; }
[ "$(stat -f '%Lp' "$KEY_FILE")" = "600" ] || { echo "$KEY_FILE must be mode 0600" >&2; exit 2; }
KEY="$(<"$KEY_FILE")"
[ -n "$KEY" ] || { echo "key file is empty" >&2; exit 2; }

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"
if [ -n "$(git status --porcelain -- Server/HerokuVoice)" ]; then
  echo "commit Server/HerokuVoice first: mirrors deploy committed history" >&2
  exit 2
fi

apps=("$PRIMARY")
for i in $(seq 2 "$COUNT"); do apps+=("$PRIMARY-m$i"); done

echo "splitting Server/HerokuVoice from $(git rev-parse --short HEAD)"
SPLIT="$(git subtree split --prefix=Server/HerokuVoice HEAD)"

for app in "${apps[@]}"; do
  echo "== $app"
  if ! heroku apps:info -a "$app" >/dev/null 2>&1; then
    heroku apps:create "$app" --stack heroku-24 --region us >/dev/null
  fi
  heroku buildpacks:set heroku/python -a "$app" >/dev/null
  heroku config:set T2S_VOICE_API_KEY="$KEY" MALLOC_ARENA_MAX=2 PYTHONUNBUFFERED=1 -a "$app" >/dev/null
  # Eco keeps one thread and no arena, the settings 512 MB survives; a tier test may have set these.
  heroku config:unset T2S_ORT_THREADS T2S_ORT_ARENA -a "$app" >/dev/null 2>&1 || true
  heroku labs:enable log-runtime-metrics -a "$app" >/dev/null 2>&1 || true
  git push -f "https://git.heroku.com/$app.git" "$SPLIT:refs/heads/main" 2>&1 | grep -E "Released v|deployed to Heroku|rror|Everything up-to-date" || true
  heroku ps:scale "web=1:$SIZE" -a "$app" >/dev/null
done

echo "== verifying"
fail=0
for app in "${apps[@]}"; do
  url="$(heroku apps:info -a "$app" --json | python3 -c 'import sys, json; print(json.load(sys.stdin)["app"]["web_url"].rstrip("/"))')"
  for _ in $(seq 1 36); do
    curl -sf --max-time 10 "$url/health" >/dev/null 2>&1 && break
    sleep 5
  done
  health="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url/health")"
  ctype="$(curl -s -o /dev/null -w '%{content_type}' --max-time 90 -X POST "$url/v1/audio/speech" \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d '{"model":"kokoro","input":"Mirror check.","voice":"af_heart","response_format":"pcm"}')"
  dyno="$(heroku ps -a "$app" --json | python3 -c 'import sys, json; d = json.load(sys.stdin); print(d[0]["size"] if d else "none")')"
  addons="$(heroku addons -a "$app" --json | python3 -c 'import sys, json; print(len(json.load(sys.stdin)))')"
  printf '%-16s health=%s render=%s dyno=%s addons=%s  %s/v1/audio/speech\n' "$app" "$health" "$ctype" "$dyno" "$addons" "$url"
  [ "$health" = "200" ] && [ "$ctype" = "audio/pcm" ] && [ "$dyno" = "Eco" ] && [ "$addons" = "0" ] || fail=1
done
exit "$fail"
```

- [ ] **Step 3: Check the script parses and the guards fire**

Run: `bash -n Server/HerokuVoice/scripts/mirrors.sh && chmod +x Server/HerokuVoice/scripts/mirrors.sh && echo parsed`
Expected: `parsed`.

Run: `T2S_VOICE_KEY_FILE=/nonexistent Server/HerokuVoice/scripts/mirrors.sh 4; echo "exit $?"`
Expected: `no key file at /nonexistent` and `exit 2`.

Run: `Server/HerokuVoice/scripts/mirrors.sh many; echo "exit $?"`
Expected: `count must be a positive integer` and `exit 2`.

- [ ] **Step 4: Document it**

Append to `Server/HerokuVoice/README.md`:

```markdown
## Mirrors

One Eco dyno renders at about 2.7x realtime, and one app cannot run more than one
Eco web dyno. `scripts/mirrors.sh [count]` (default 4) deploys this directory to
`kokoro-t2s`, `kokoro-t2s-m2`, … as identical Eco apps from one `git subtree split`,
sets the same key on each from `~/.t2s/heroku-voice-key` (mode 0600, never printed),
scales each to exactly `web=1:eco`, and verifies health, an authenticated render,
the dyno size, and that there are no add-ons. It is safe to re-run.

The app lists every mirror's `/v1/audio/speech` URL in Cloud voices, one per line;
the first is the route's identity and the rest are interchangeable with it. The
render scheduler then holds one request in flight per mirror.
```

- [ ] **Step 5: Commit the script, then deploy**

```bash
git add Server/HerokuVoice/scripts/mirrors.sh Server/HerokuVoice/README.md
git commit -m "One script deploys the voice service to N identical Eco mirrors and verifies each"
```

Then, from the repository root:

Run: `Server/HerokuVoice/scripts/mirrors.sh 4 2>&1 | tee /tmp/mirrors-deploy.log | grep -v "Bearer"`
Expected: four `== kokoro-t2s…` blocks each ending in `Released v<n>` and `deployed to Heroku`, then four verification lines all reading `health=200 render=audio/pcm dyno=Eco addons=0`, exit 0. Builds take about three minutes each; the script waits.

If `heroku apps:create` fails with a name already taken, change `PRIMARY`'s suffix scheme in the script (for example `-mirror2`) and re-run; the primary `kokoro-t2s` already exists and is untouched by that.

- [ ] **Step 6: Record the four URLs**

Run: `for a in kokoro-t2s kokoro-t2s-m2 kokoro-t2s-m3 kokoro-t2s-m4; do heroku apps:info -a $a --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["app"]["web_url"].rstrip("/") + "/v1/audio/speech")'; done`
Expected: four HTTPS URLs. These go into Cloud voices in Task 11.

---

### Task 11: Live acceptance and the record

**Files:**
- Create: `docs/superpowers/evidence/2026-09-11-eco-mirrors-acceptance.log`
- Modify: `docs/HANDOFF.md` (a new entry under the Heroku section)

**Interfaces:**
- Consumes: four deployed mirrors (Task 10), a phone with the app built from this branch (Task 8's build), the owner at the phone.

- [ ] **Step 1: Configure the phone**

On the phone, in Preferences → Cloud voices: paste the four URLs from Task 10 Step 6 into the endpoint field, one per line, primary first; model `kokoro`; voice `af_heart`; request rate `20`; the key from `~/.t2s/heroku-voice-key` (transcribe it; do not paste it into any chat or log). Save. Tap **Test voice** and confirm speech.

- [ ] **Step 2: Measure aggregate throughput from the Mac while the phone rests**

Run this from the repository root; it fires one render per mirror at once and reports audio seconds delivered per wall second:

```bash
KEY="$(<~/.t2s/heroku-voice-key)"
URLS=$(for a in kokoro-t2s kokoro-t2s-m2 kokoro-t2s-m3 kokoro-t2s-m4; do heroku apps:info -a $a --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["app"]["web_url"].rstrip("/") + "/v1/audio/speech")'; done)
TEXT="She counted the boats twice, then a third time, because the numbers refused to agree with each other. Somewhere past the breakwater a bell was ringing."
start=$(date +%s.%N)
i=0; for u in $URLS; do i=$((i+1))
  curl -s -o /tmp/mirror-$i.pcm --max-time 90 -X POST "$u" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "$(python3 -c "import json,sys; print(json.dumps({'model':'kokoro','input':sys.argv[1],'voice':'af_heart','response_format':'pcm'}))" "$TEXT")" &
done; wait
end=$(date +%s.%N)
python3 - <<PY
import os, glob
wall = $end - $start
audio = sum(os.path.getsize(p) for p in glob.glob('/tmp/mirror-*.pcm')) / 2 / 24000
print(f"wall {wall:.1f} s, audio {audio:.1f} s, aggregate realtime {wall/audio:.2f}x (below 1.0 keeps ahead of playback)")
PY
```

Expected: about 0.7x. Record the line.

- [ ] **Step 3: Play a chapter**

On the phone, open a document with the hosted voice selected and play from the start of a chapter for at least ten minutes. Watch for a stall after the first utterance (a pause with the play button still showing playing). Note whether one occurred and roughly when.

- [ ] **Step 4: Read every mirror's logs**

Run:

```bash
for a in kokoro-t2s kokoro-t2s-m2 kokoro-t2s-m3 kokoro-t2s-m4; do
  echo "== $a"
  heroku logs -a $a -n 1500 2>/dev/null | grep -cE "R14|R15|H12" | sed 's/^/  errors: /'
  heroku logs -a $a -n 1500 2>/dev/null | grep -oE "memory_rss=[0-9.]+MB" | sort -t= -k2 -n | tail -1 | sed 's/^/  peak: /'
  heroku ps -a $a 2>/dev/null | grep -E "Eco dyno usage" | sed 's/^/  /'
done
```

Expected: `errors: 0` on every mirror, peaks under `512.00MB`, and each app's Eco hours consumed.

- [ ] **Step 5: Write the evidence and the handoff**

Create `docs/superpowers/evidence/2026-09-11-eco-mirrors-acceptance.log` containing, verbatim: the four verification lines from Task 10 Step 5, the aggregate-throughput line from Step 2, the chapter-play observation from Step 3, and Step 4's output.

Add to `docs/HANDOFF.md`, at the end of the "Heroku Kokoro Eco pilot" section:

```markdown
**Mirrors (2026-09-11, late):** one Eco dyno measured 2.7x realtime and Standard-2X 1.96x, neither
ahead of playback, so the route now runs on four identical Eco apps (`kokoro-t2s`, `-m2`, `-m3`,
`-m4`; `Server/HerokuVoice/scripts/mirrors.sh`) and the scheduler holds one render in flight per
mirror. Design: `docs/superpowers/specs/2026-09-11-eco-voice-mirrors-design.md`. Measured
acceptance: `docs/superpowers/evidence/2026-09-11-eco-mirrors-acceptance.log`. The key lives at
`~/.t2s/heroku-voice-key` (0600) on the Mac. Still owed: server streaming for a first sound under
~3 s; its own spec.
```

- [ ] **Step 6: Commit, or scale to zero**

If Step 3 saw no stall and Step 4 read zero errors:

```bash
git add docs/superpowers/evidence/2026-09-11-eco-mirrors-acceptance.log docs/HANDOFF.md
git commit -m "Record the Eco mirrors' acceptance run"
```

If a chapter stalled or any mirror logged R14/R15/H12: keep the evidence, scale every mirror to zero, and report the measured blocker instead of committing an acceptance:

```bash
for a in kokoro-t2s kokoro-t2s-m2 kokoro-t2s-m3 kokoro-t2s-m4; do heroku ps:scale web=0 -a $a; done
git add docs/superpowers/evidence/2026-09-11-eco-mirrors-acceptance.log
git commit -m "Record the Eco mirrors' failed acceptance run; every mirror scaled to zero"
```

No paid upgrade either way.
