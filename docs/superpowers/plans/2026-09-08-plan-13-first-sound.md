# Plan 13 — First sound: the quick wins from the performance audit

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

_2026-09-08. Branch `plan-13-first-sound` off `dev` @ b951d86, in the worktree
`.worktrees/plan-13-first-sound`. Written from the performance audit; the owner said "you decide how
to best proceed". Another session is working in the main checkout on Plan 12 (the Player sheet
retired) and owns `App/T2SReader/Root/`, `App/T2SReader/Player/`, `App/T2SReader/Collection/`,
`App/T2SReader/Queue/` and `App/T2SReader/Reader/ThinScrubber.swift` — this plan touches none of them._

**Goal:** Make the first sound after a tap, an import or a launch come sooner, and stop the app doing
work at the wrong time — the audit's single-task recommendations (#1, #3, #4, #8, #11 and the cheap
parts of #5), leaving the streaming render (#2) for its own plan.

**Architecture:** Seven small changes in the engine, render, store and persistence layers, each
behind an existing seam: the Phone scheme's run configuration; the engine's `load()` (the G2P joins
the warm-up); `RenderPolicy`'s prime tier (never planned until now) driven from `PrepareRunner` after
an import and at launch; a `RecentAudioStore` memory tier in front of `FileAudioStore` so the live path
plays the render instead of decoding the cache; a batch `contains` and a cheaper `RenderKey` on the
open path; `PrepareRunner` writing a chapter once instead of per utterance; and `PlaybackCoordinator`
stepping the rate down when the measured RTF says the current one will stall.

**Tech Stack:** Swift 6.2, swift-testing; `swift test` for the root package; `scripts/test-kokoro.sh`
(xcodebuild, macOS, `-only-testing:` for the one model-backed test); xcodegen for the scheme check.

**Spec:** [docs/superpowers/specs/2026-09-08-performance-audit.md](../specs/2026-09-08-performance-audit.md)
§2 (the ranked table), §3.2, §3.3, §3.5, §5.2, §5.4, §6.1; the design spec
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](../specs/2026-09-01-t2s-reader-design.md)
§3.4.1 (tiers), §3.6 (rate coupling), §3.7.3 (audio is cache).

## Global Constraints

- **Never play audio on the owner's Mac.** No test or tool in this plan plays anything; the Kokoro
  engine test writes buffers only. Never launch the simulator.
- **Do not touch the other session's files** (listed above). If a task seems to need one of them,
  stop and record it in the ledger instead.
- `Versions.normalizer` and `Versions.segmenter` do not change: nothing here alters spoken text.
- Rendered audio is cache, never truth (spec §3.7.3): every new tier or coalescing must be safe to
  lose — `PlaybackCoordinator.reconcileWithStore` and `fill()` self-heal a missing clip.
- Swift 6 language mode, strict concurrency: every new type is `Sendable` or an actor; nothing new
  captures a non-`Sendable` value across an actor hop.
- `KokoroCoreMLEngine.Options`'s initializer defaults stay upstream's.
- `scripts/test-kokoro.sh` sweeps Core ML caches shared by every checkout and each model-backed test
  compiles ~350 MB into `$TMPDIR`: run it only with `-only-testing:` and keep ~10 GB free
  (`df -h .`). The root package's `swift test` is the gate for every other task.
- Commit per task from the worktree (`cd .worktrees/plan-13-first-sound && git add … && git commit`),
  message in the repo's voice ("Plan 13 Task N: what changed — why").

---

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **The phone runs Release.** `run: config: Release` on the Phone scheme; the recipe in HANDOFF and README say so. | `App/project.yml`, `docs/HANDOFF.md`, `README.md` | `xcodegen generate` in the worktree's `App/`, then the generated `Phone.xcscheme` shows `buildConfiguration = "Release"` under `LaunchAction` |
| 2 | **The G2P is built in the warm-up.** `KokoroCoreMLEngine.load()` builds the American G2P after the stages; `isG2PLoaded` for the test. | `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift`, its tests, `App/T2SReader/System/KokoroComposition.swift` (a comment) | `scripts/test-kokoro.sh -only-testing:…/preloadBuildsTheG2P` |
| 3 | **The prime tier runs.** `RenderPolicy` primes from the resume index; `PrepareRunner.prime(_:)` and `primeContinueDocument()`; `ImportModel.afterImport`; wired in `AppEnvironment` and `T2SReaderApp`. | `Sources/T2SCore/Render/RenderPolicy.swift`, `Sources/T2SApp/Playback/PrepareRunner.swift`, `Sources/T2SApp/Import/ImportModel.swift`, `App/T2SReader/AppEnvironment.swift`, `App/T2SReader/T2SReaderApp.swift`, tests | `swift test` |
| 4 | **The live path plays the render.** `RecentAudioStore` in front of the file store; `AudioStore.contains(_ keys:)`; `RenderKey` hex without `String(format:)`; batch reconcile in the coordinator and Prepare. | `Sources/T2SCore/Render/RecentAudioStore.swift` (new), `AudioStore.swift`, `FileAudioStore.swift`, `InMemoryAudioStore.swift`, `RenderKey.swift`, `Sources/T2SAudio/PlaybackCoordinator.swift`, `Sources/T2SApp/Playback/PrepareRunner.swift`, `App/T2SReader/Shared/SharedLibraryFactory.swift`, tests | `swift test` |
| 5 | **Prepare writes a chapter once.** Chapter blobs are saved when the chapter changes, every 10 s, and at the end of a group — not per utterance. | `Sources/T2SApp/Playback/PrepareRunner.swift`, tests | `swift test` |
| 6 | **The rate steps down before playback stalls.** `measuredRTF` and `availableRates` refresh on every render; a rate above the sustainable cap is lowered and `rateLoweredTo` says so. | `Sources/T2SAudio/PlaybackCoordinator.swift`, tests | `swift test` |
| 7 | **Docs.** HANDOFF resume section; the audit's progress note; spec §3.4.1 prime row and rev 13. | `docs/` | review |

## Decisions taken without the owner (each with its cost if wrong)

- **Release for the Phone scheme's Run action, Debug for Simulator.** The owner installs by pressing
  Run; the audit found every listen may have been `-Onone`. Cost: the `T2S_KOKORO_DEBUG_OVERRIDE`
  escape hatch and Debug-only asserts are off on the phone — both are development tools, not the
  owner's.
- **Prime is refused while a Prepare pass runs, and vice versa** (`isRunning`). A launch prime is
  three utterances. But nothing retriggers a foreground Prepare pass that was refused because a prime
  held the slot: `RootPager.startForegroundPrepareIfNeeded()` runs at scene activation, on a
  device/queue/player-state change, and the background task runs on its own schedule — the prime's
  completion is not one of those. So a pass refused on a charging launch waits for the next such
  event, not for the prime to finish. Cost: on a charging launch that is never backgrounded and never
  changes power state, Prepare may not run at all that session. The retrigger belongs to
  `App/T2SReader/Root/RootPager.swift`, which is the other session's file.
- **The memory tier holds the last eight renders** (~1 MB each at 24 kHz mono float for 10 s of
  speech, at most ~8 MB). It is consulted only when the base store still holds the key, so eviction
  and the "cache, never truth" rule are unchanged. Cost: 8 MB of resident memory while rendering.
- **Chapter writes are coalesced to "chapter changed, or 10 s"**, not "chapter complete": a book of
  600-utterance chapters would otherwise write nothing for twenty minutes. Cost: a crash inside
  Prepare loses ≤ 10 s of chapter metadata; the audio is on disk and `reconcileWithStore` recovers it.
- **A lowered rate is published, not narrated.** `rateLoweredTo` is an observable the Reader can show
  once; the Reader's chrome belongs to the other session's plan, so the line of UI is deferred.
- **The continue-document is primed from `T2SReaderApp`'s scene, not `AppEnvironment.init`**: the
  background Prepare task also builds an `AppEnvironment`, and a prime there would race the prepare.

## Deferred (next plan)

- **Streaming the first sound** (audit #2): `synthesizeStreaming`, `enqueue(_:tag:isFinal:)`, the
  coordinator's "head in flight". Needs the quality probe on the seam a short first piece makes.
- **The open path's `play()` gate on `reconcileWithStore`** (audit §5.4): batched here, not removed.
- **`LibraryModel.refresh` decoding every book** (audit §5.4): needs a schema addition; and the Queue
  page is the other session's.
- Buckets 3 s / 10 s (#9), concurrent bucket-lazy loading (#10), the OOV phoneme cache and hn-NSF
  overlap (#12), the normalizer folding (#13), the UI tick churn (#7 — the other session's files).

---

### Task 1: The phone runs Release

**Files:**
- Modify: `App/project.yml` (the `schemes:` block at the end)
- Modify: `docs/HANDOFF.md` (the install recipe's "build configuration Release (Edit Scheme → Run → Info)" line)
- Modify: `README.md` ("Running the app" — the Phone bullet)

**Interfaces:**
- Consumes: nothing.
- Produces: the Phone scheme's Run action uses the Release configuration.

- [ ] **Step 1: Confirm the current state**

Run: `cd .worktrees/plan-13-first-sound && grep -n -A8 "^schemes:" App/project.yml`
Expected: `Phone:` … `run:` … `config: Debug`.

- [ ] **Step 2: Change the Phone scheme's run configuration**

Edit `App/project.yml`; the block currently reads:

```yaml
schemes:
  Phone:
    build:
      targets:
        T2SReaderKokoro: all
    run:
      config: Debug
    archive:
      config: Release
```

Make it:

```yaml
schemes:
  # Phone runs Release: it is the build the owner listens to, and every Swift-side stage of the
  # render — the hn-NSF DSP, the seam and tail-click scans, the crossfade, the tokenizer, the
  # segmenter, the Reader's typesetter — runs -Onone under Debug, 10–50× slower for tight loops
  # (docs/superpowers/specs/2026-09-08-performance-audit.md §6.1). The spike that measured RTF 0.18
  # was a Release harness. The MLX development override (`T2S_KOKORO_DEBUG_OVERRIDE`) is compiled
  # out of Release; set the Run configuration back to Debug by hand for that one experiment.
  Phone:
    build:
      targets:
        T2SReaderKokoro: all
    run:
      config: Release
    archive:
      config: Release
```

Leave the `Simulator` scheme as it is (`run: config: Debug`).

- [ ] **Step 3: Regenerate the project and verify the scheme**

Run:
```bash
cd .worktrees/plan-13-first-sound/App && xcodegen generate --quiet && grep -n "buildConfiguration" T2SReader.xcodeproj/xcshareddata/xcschemes/Phone.xcscheme
```
Expected: the `LaunchAction` line shows `buildConfiguration = "Release"` (the `TestAction` and
`AnalyzeAction` may still say Debug; only `LaunchAction` and `ArchiveAction` matter). Then the same
grep on `Simulator.xcscheme` shows `LaunchAction … "Debug"`. The generated project is git-ignored.

- [ ] **Step 4: Update the recipe in HANDOFF and README**

In `docs/HANDOFF.md`, find the line containing `build configuration Release (Edit Scheme → Run → Info)`
and replace that phrase with:

```
build configuration Release — the Phone scheme's Run action is Release since Plan 13 (`App/project.yml`), so nothing to set
```

In `README.md`, in the **Phone** bullet under "Running the app" (it begins `- **Phone** (the
\`T2SReaderKokoro\` target) — device only`), append this sentence at the end of the bullet:

```
Its Run action builds Release: the app you listen to is the optimised one, and the RTF the app
measures is the one the spike measured (`docs/superpowers/specs/2026-09-08-performance-audit.md`
§6.1). The Simulator scheme stays Debug.
```

- [ ] **Step 5: Commit**

```bash
cd .worktrees/plan-13-first-sound && git add App/project.yml docs/HANDOFF.md README.md && git commit -m "Plan 13 Task 1: the Phone scheme runs Release — the listen is the optimised build, as the spike's RTF was"
```

---

### Task 2: The G2P is built in the warm-up

**Files:**
- Modify: `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift` — `preload()` doc comment (~line 160), `load()` (~lines 166–200), a new `isG2PLoaded` beside `loadCount` (~line 117)
- Modify: `App/T2SReader/System/KokoroComposition.swift` — the comment above `status.update(.preparing)` (~line 104)
- Test: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroCoreMLEngineTests.swift`

**Interfaces:**
- Consumes: `KokoroCoreMLEngine.load()`, `g2p(british:)` (both existing, private).
- Produces: `KokoroCoreMLEngine.isG2PLoaded: Bool` (internal, test-only observability, like `loadCount`).

- [ ] **Step 1: Write the failing test**

Add to `KokoroCoreMLEngineTests` after `loadsTheStagesOnceWhenAPreloadAndARenderArriveTogether`:

```swift
    /// The launch warm-up loads the stages so the first utterance does not wait for them; the G2P's
    /// two 3 MB lexicons and its fallback network are built the same way, or the first sentence a
    /// reader hears pays for them after the tap
    /// (`docs/superpowers/specs/2026-09-08-performance-audit.md` §3.2).
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func preloadBuildsTheG2P() async throws {
        let engine = try await Self.engineWithRealResources()
        #expect(await engine.isG2PLoaded == false)
        try await engine.preload()
        #expect(await engine.isG2PLoaded)
    }
```

- [ ] **Step 2: Run it to see it fail to compile**

Run:
```bash
cd .worktrees/plan-13-first-sound && df -h . | tail -1 && scripts/test-kokoro.sh -only-testing:T2SKokoroTests/KokoroCoreMLEngineTests/preloadBuildsTheG2P
```
Expected: a compile error, `value of type 'KokoroCoreMLEngine' has no member 'isG2PLoaded'`. (The
first xcodebuild in this worktree may rebuild for several minutes; that is the package, not the test.)

- [ ] **Step 3: Build the G2P at the end of `load()`**

In `KokoroCoreMLEngine.swift`, next to `private(set) var loadCount = 0`, add:

```swift
    /// Whether the American G2P has been built. Internal for one test: `preload()` must build it, or
    /// the first sentence of a session pays for two lexicons and a network after the tap.
    var isG2PLoaded: Bool { americanG2P != nil }
```

In `load()`, after `self.loaded = loaded` and before `return loaded`, add:

```swift
            // The G2P's lexicons (two 3 MB JSON files, merged) and its fallback network are the other
            // thing the first sentence would otherwise wait for; build the American one here so the
            // launch warm-up pays it. The British G2P stays lazy: a `b*` voice is a choice, not the
            // default, and its lexicon is another 9 MB.
            _ = g2p(british: false)
```

Update the doc comment on `preload()` from

```swift
    /// Loads the eight stages, compiling them first when the staging is not precompiled, and the
    /// vocoder weights. `synthesize` calls it lazily on first use; a caller that would rather pay the
    /// seconds before playback starts can call it itself.
```
to
```swift
    /// Loads the eight stages, compiling them first when the staging is not precompiled, the
    /// vocoder weights, and the American G2P. `synthesize` calls it lazily on first use; a caller
    /// that would rather pay the seconds before playback starts can call it itself.
```

- [ ] **Step 4: Run the test to see it pass**

Run the same command as Step 2. Expected: `Test preloadBuildsTheG2P() passed` and `TEST SUCCEEDED`.
Then run the neighbour once, to prove the shared load still counts one:
```bash
scripts/test-kokoro.sh -only-testing:T2SKokoroTests/KokoroCoreMLEngineTests/loadsTheStagesOnceWhenAPreloadAndARenderArriveTogether
```
Expected: passed.

- [ ] **Step 5: Say so in the composition root's comment**

In `App/T2SReader/System/KokoroComposition.swift`, the comment

```swift
            // Loading eight stages takes seconds on a modern phone and minutes on an A13. Pay them
            // now, while the reader is still choosing a book, rather than at the first utterance.
```
becomes
```swift
            // Loading eight stages takes seconds on a modern phone and minutes on an A13, and the
            // G2P's lexicons a few hundred milliseconds more. Pay them now, while the reader is still
            // choosing a book, rather than at the first utterance.
```

- [ ] **Step 6: Commit**

```bash
cd .worktrees/plan-13-first-sound && git add Packages/T2SKokoro App/T2SReader/System/KokoroComposition.swift && git commit -m "Plan 13 Task 2: the warm-up builds the G2P — the first sentence no longer parses two lexicons after the tap"
```

---

### Task 3: The prime tier runs — after an import and at launch

**Files:**
- Modify: `Sources/T2SCore/Render/RenderPolicy.swift:124-128` (the tier-2 loop)
- Modify: `Sources/T2SApp/Playback/PrepareRunner.swift` — `PrepareRunReason`, new `prime(_:)` and `primeContinueDocument()`, a shared `render(reason:documents:jobs:)` tail
- Modify: `Sources/T2SApp/Import/ImportModel.swift` — `afterImport`
- Modify: `App/T2SReader/AppEnvironment.swift` — wire `afterImport`
- Modify: `App/T2SReader/T2SReaderApp.swift` — `.task` for the launch prime
- Test: `Tests/T2SCoreTests/Render/RenderPolicyTests.swift`, `Tests/T2SAppTests/PrepareRunnerTests.swift`, `Tests/T2SAppTests/ImportModelTests.swift`

**Interfaces:**
- Consumes: `RenderPolicy.plan(_:)`, `PolicyInput.primes`, `RenderSnapshot.resumeIndex`, `PrepareRunner.loadDocuments(lastPlayed:queue:)` and `render(_:document:)` (existing, private).
- Produces: `PrepareRunReason.prime`; `PrepareRunner.primeSeconds: TimeInterval = 30` (static);
  `PrepareRunner.prime(_ documentID: UUID) async -> PrepareRunResult`;
  `PrepareRunner.primeContinueDocument() async -> PrepareRunResult`;
  `ImportModel.afterImport: (@MainActor ([DocumentSummary]) -> Void)?`.

- [ ] **Step 1: Write the failing policy test**

In `Tests/T2SCoreTests/Render/RenderPolicyTests.swift`, after `primeRendersTheFirstThirtySeconds`, add:

```swift
    /// The continue-document is primed at launch from where the reader left it, not from page one.
    @Test func primeStartsAtTheResumeIndex() {
        let jobs = RenderPolicy.plan(input(primes: [b], docs: [snap(b, resume: 50)]))
        #expect(indices(jobs, b, .prime) == [50, 51, 52])
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd .worktrees/plan-13-first-sound && swift test --filter RenderPolicyTests 2>&1 | tail -5`
Expected: `primeStartsAtTheResumeIndex` fails (`[0, 1, 2]` ≠ `[50, 51, 52]`).

- [ ] **Step 3: Prime from the resume index**

In `RenderPolicy.plan`, the tier-2 loop

```swift
        // Tier 2: prime newly imported documents.
        for id in input.primes {
            if let doc = input.documents[id] { walk(doc, from: 0, budget: input.primeSeconds, tier: .prime) }
        }
```
becomes
```swift
        // Tier 2: prime — a newly imported document from its start, the continue-document from where
        // the reader left it (spec §3.4.1; `resumeIndex` is 0 for a new import).
        for id in input.primes {
            if let doc = input.documents[id] { walk(doc, from: doc.resumeIndex, budget: input.primeSeconds, tier: .prime) }
        }
```

Run the filter again. Expected: all `RenderPolicyTests` pass.

- [ ] **Step 4: Write the failing runner tests**

In `Tests/T2SAppTests/PrepareRunnerTests.swift`, add inside the suite:

```swift
    /// Spec §3.4.1 tier 2: the first 30 s of a document, any power state, so its first tap plays
    /// with no spin-up. Never planned by anything until Plan 13 (the audit's #3).
    @Test func primeRendersTheFirstThirtySecondsOnBattery() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: defaults, arbiter: RenderArbiter())

        let result = await runner.prime(id)

        #expect(result.reason == .prime)
        #expect(result.stopReason == .completed)
        #expect(result.renderedUtterances == 3)                                  // the fake book is ~3.3 s: all of it
        #expect(result.documentIDs == [id])
        #expect(result.recordedAt == nil)                                       // a prime is not a Prepare run
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) == nil)
        let stored = try #require(try await fixtures.store.timeline(for: id)).timeline
        let refs = stored.chapters.flatMap(\.utterances).map(\.audioRef)
        #expect(refs.allSatisfy { $0 != nil })
    }

    /// The continue-document is whichever was played last; nothing played means nothing to prime.
    @Test func primeContinueDocumentPicksTheLastPlayed() async throws {
        let fixtures = try AppFixtures()
        let first = try await fixtures.importFake()
        let second = try await fixtures.importFake()
        let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: defaults, arbiter: RenderArbiter())

        let nothing = await runner.primeContinueDocument()
        #expect(nothing.stopReason == .completed && nothing.renderedUtterances == 0)

        try await fixtures.store.savePosition(Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0), for: second)
        let primed = await runner.primeContinueDocument()
        #expect(primed.documentIDs == [second])
        #expect(primed.renderedUtterances > 0)
        _ = first
    }
```

- [ ] **Step 5: Run them to see them fail to compile**

Run: `swift test --filter PrepareRunnerTests 2>&1 | tail -5`
Expected: `value of type 'PrepareRunner' has no member 'prime'`.

- [ ] **Step 6: Add the prime entry points to `PrepareRunner`**

In `Sources/T2SApp/Playback/PrepareRunner.swift`:

`PrepareRunReason` gains a case:

```swift
public enum PrepareRunReason: Hashable, Sendable {
    case foreground
    case backgroundProcessing
    /// Spec §3.4.1 tier 2: the first ~30 s of one document, any power state.
    case prime
}
```

After the `cancel()` method, add:

```swift
    /// Spec §3.4.1 tier 2 (`RenderPolicy`'s `primeSeconds`).
    public static let primeSeconds: TimeInterval = 30

    /// Renders the first ``primeSeconds`` of `documentID` from its resume position, in any power
    /// state, so its next tap plays with no spin-up: after an import (from the start) and at launch
    /// for the continue-document (from where the reader left it). Refused while a Prepare pass runs —
    /// `.skipped(.alreadyRunning)` — since the two share one scheduler slot; a prime is three
    /// utterances, so nothing waits long. Never records a Prepare run.
    public func prime(_ documentID: UUID) async -> PrepareRunResult {
        guard !isRunning else {
            return finish(PrepareRunResult(reason: .prime, stopReason: .skipped(.alreadyRunning)))
        }
        isRunning = true
        cancelRequested = false
        lastError = nil
        defer {
            isRunning = false
            currentScheduler = nil
        }

        let documents = await loadDocuments(lastPlayed: documentID, queue: [])
        guard let document = documents.first else {
            return finish(PrepareRunResult(reason: .prime, stopReason: .completed))
        }
        var input = PolicyInput(documents: [document.id: document.snapshot], primes: [document.id], device: .unplugged)
        input.primeSeconds = Self.primeSeconds
        let jobs = RenderPolicy.plan(input).filter { $0.tier == .prime }

        var result = PrepareRunResult(reason: .prime, stopReason: .completed)
        guard !jobs.isEmpty else { return finish(result) }
        let groupResult = await render(jobs, document: document)
        result.renderedUtterances = groupResult.renderedUtterances
        result.preparedSeconds = groupResult.preparedSeconds
        if groupResult.renderedUtterances > 0 { result.documentIDs = [document.id] }
        if groupResult.storageFull {
            result.stopReason = .storageFull
        } else if cancelRequested || Task.isCancelled {
            result.stopReason = .cancelled
        }
        return finish(result)
    }

    /// ``prime(_:)`` for the continue-document — the one played most recently — so the mini-player's
    /// first tap after a launch is instant. Nothing played yet means nothing to do.
    public func primeContinueDocument() async -> PrepareRunResult {
        let summaries = (try? await store.summaries()) ?? []
        guard let last = summaries.filter({ $0.lastPlayedAt != nil })
            .max(by: { $0.lastPlayedAt! < $1.lastPlayedAt! })?.id
        else { return finish(PrepareRunResult(reason: .prime, stopReason: .completed)) }
        return await prime(last)
    }
```

`PolicyInput.init` already takes `primes:` and `device:` (see `Sources/T2SCore/Render/RenderPolicy.swift:86-88`);
`loadDocuments(lastPlayed:queue:)` puts `lastPlayed` first, so `documents.first` is the document
asked for. `finish(_:)`, `render(_:document:)`, `isRunning`, `cancelRequested` and `currentScheduler`
already exist in the file.

- [ ] **Step 7: Run the runner tests to see them pass**

Run: `swift test --filter PrepareRunnerTests 2>&1 | tail -5`
Expected: all pass, including the four that were there.

- [ ] **Step 8: Write the failing import-hook test**

In `Tests/T2SAppTests/ImportModelTests.swift`, add inside the suite:

```swift
    /// Whoever wires the model — the app — primes the new documents so their first tap plays at once;
    /// the hook carries the summaries so it need not look them up again.
    @Test func afterImportReceivesEveryImportedDocument() async throws {
        let f = try AppFixtures()
        let model = ImportModel(library: f.library, extractor: FakeExtractor())
        var received: [[UUID]] = []
        model.afterImport = { docs in received.append(docs.map(\.id)) }

        await model.importText(title: "", body: "A pasted note.")
        guard case .done(let docs) = model.phase else { Issue.record("expected done, got \(model.phase)"); return }
        #expect(received == [[docs[0].id]])

        await model.importText(title: "", body: "   ")                       // fails before importing
        #expect(received.count == 1)
    }
```

- [ ] **Step 9: Run it to see it fail to compile**

Run: `swift test --filter ImportModelTests 2>&1 | tail -5`
Expected: `value of type 'ImportModel' has no member 'afterImport'`.

- [ ] **Step 10: Add the hook**

In `Sources/T2SApp/Import/ImportModel.swift`, after `public private(set) var fileRows: [FileRow] = []`:

```swift
    /// Called on the main actor with every document an import produced, after `phase` is `.done`.
    /// The app primes them (spec §3.4.1 tier 2); a test counts them. Nil in the Share Extension,
    /// which imports and hands off.
    public var afterImport: (@MainActor ([DocumentSummary]) -> Void)?
```

In `importFiles(_:)`, the last line

```swift
        phase = imported.isEmpty ? .failed("Nothing could be imported.") : .done(imported)
```
becomes
```swift
        phase = imported.isEmpty ? .failed("Nothing could be imported.") : .done(imported)
        if !imported.isEmpty { afterImport?(imported) }
```

In `finish(_:)`, the line `phase = .done([summary])` becomes:

```swift
            phase = .done([summary])
            afterImport?([summary])
```

- [ ] **Step 11: Run the import tests to see them pass**

Run: `swift test --filter ImportModelTests 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 12: Wire the app**

In `App/T2SReader/AppEnvironment.swift`, in `init`, after the line `prepareRunner.voiceRouting = voiceRouting`, add:

```swift
        // Spec §3.4.1 tier 2: a new document's first 30 s render now, on any power state, so its
        // first tap plays with no spin-up. One at a time, behind whatever the player is rendering —
        // the arbiter gives play-ahead the next utterance.
        importModel.afterImport = { [prepareRunner] documents in
            Task { for document in documents { _ = await prepareRunner.prime(document.id) } }
        }
```

In `App/T2SReader/T2SReaderApp.swift`, after the `.onAppear { … }` modifier on `RootPager()`, add:

```swift
                    .task {
                        // The continue-document's next 30 s, from where the reader left it, so the
                        // mini-player's first tap after a launch is instant (spec §3.4.1 tier 2).
                        // Here and not in `AppEnvironment.init`: the background Prepare task builds an
                        // environment too, and a prime there would race the prepare for the one slot.
                        _ = await environment.prepareRunner.primeContinueDocument()
                    }
```

- [ ] **Step 13: Build the app target for the simulator to prove it compiles**

Run: `cd .worktrees/plan-13-first-sound && scripts/build-app.sh 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (this builds the Simulator target; it does not launch anything).

- [ ] **Step 14: Run the whole root suite and commit**

Run: `swift test 2>&1 | tail -3` — expected: every test passes (365 + 4 new).

```bash
git add Sources/T2SCore/Render/RenderPolicy.swift Sources/T2SApp/Playback/PrepareRunner.swift Sources/T2SApp/Import/ImportModel.swift App/T2SReader/AppEnvironment.swift App/T2SReader/T2SReaderApp.swift Tests/T2SCoreTests/Render/RenderPolicyTests.swift Tests/T2SAppTests/PrepareRunnerTests.swift Tests/T2SAppTests/ImportModelTests.swift
git commit -m "Plan 13 Task 3: the prime tier runs — a new document's first 30 s after import, the continue-document's from its resume position at launch"
```

---

### Task 4: The live path plays the render

**Files:**
- Create: `Sources/T2SCore/Render/RecentAudioStore.swift`
- Modify: `Sources/T2SCore/Render/AudioStore.swift` (the protocol + a default), `FileAudioStore.swift`, `InMemoryAudioStore.swift` (batch `contains`), `RenderKey.swift` (hex)
- Modify: `Sources/T2SAudio/PlaybackCoordinator.swift:134-150` (`reconcileWithStore`)
- Modify: `Sources/T2SApp/Playback/PrepareRunner.swift` (`loadDocuments`, ~lines 179-193)
- Modify: `App/T2SReader/Shared/SharedLibraryFactory.swift`, `App/T2SReader/AppEnvironment.swift` (the `audioStore` type)
- Test: `Tests/T2SCoreTests/Render/AudioStoreTests.swift`, `Tests/T2SCoreTests/Render/RenderKeyTests.swift`, `Tests/T2SCoreTests/Render/RecentAudioStoreTests.swift` (new)

**Interfaces:**
- Consumes: `AudioStore`, `LRUIndex`, `PCMAudio`, `RenderKey`.
- Produces: `AudioStore.contains(_ keys: [RenderKey]) async -> [Bool]` (protocol requirement with a
  default implementation); `public actor RecentAudioStore: AudioStore` with
  `init(base: any AudioStore, keeping limit: Int = 8)`; `RenderKey` unchanged in value.

- [ ] **Step 1: Pin the key's digest and the batch contains — failing tests**

In `Tests/T2SCoreTests/Render/RenderKeyTests.swift`, add:

```swift
    /// The digest is the file name on disk: it must never move when the encoding does.
    @Test func digestIsPinned() {
        #expect(key().rawValue == "c1b30d0954935e8bc636cb7e8768cce031292b9ea66e5e4d544459d8cf44bfc3")
    }
```

In `Tests/T2SCoreTests/Render/AudioStoreTests.swift`, add:

```swift
    @Test func containsManyAnswersInOrder() async throws {
        for (name, s) in stores() {
            try await s.write(pcm(1), for: key(1))
            try await s.write(pcm(1), for: key(3))
            #expect(await s.contains([key(1), key(2), key(3)]) == [true, false, true], "\(name)")
            #expect(await s.contains([]) == [], "\(name)")
        }
    }
```

Create `Tests/T2SCoreTests/Render/RecentAudioStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import T2SCore

/// Counts decodes: the memory tier exists so the live path never decodes what it just rendered.
final class CountingCodec: AudioCodec, @unchecked Sendable {
    let identifier = "pcm-f32le"
    private let inner = RawPCMCodec()
    private let lock = NSLock()
    private var _decodes = 0
    var decodes: Int { lock.withLock { _decodes } }
    func encode(_ pcm: PCMAudio) throws -> Data { try inner.encode(pcm) }
    func decode(_ data: Data) throws -> PCMAudio {
        lock.withLock { _decodes += 1 }
        return try inner.decode(data)
    }
}

@Suite struct RecentAudioStoreTests {
    let doc = UUID()
    func key(_ i: Int) -> RenderKey { RenderKey(documentID: doc, utteranceIndex: i, voiceID: "v", engineID: "fake", normalizerVersion: 1, segmenterVersion: 1) }
    func pcm(_ i: Int) -> PCMAudio { PCMAudio(sampleRate: 1000, samples: Array(repeating: Float(i), count: 100)) }

    @Test func aRecentRenderIsReadWithoutDecoding() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 1_000_000)
        let store = RecentAudioStore(base: base, keeping: 2)
        try await store.write(pcm(1), for: key(1))
        #expect(try await store.read(key(1)) == pcm(1))
        #expect(codec.decodes == 0)
        #expect(await store.contains(key(1)))
        #expect(await store.stats().entries == 1)                         // the base's numbers, not the tier's
    }

    @Test func onlyTheLastFewStayInMemory() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 1_000_000)
        let store = RecentAudioStore(base: base, keeping: 2)
        for i in 1...3 { try await store.write(pcm(i), for: key(i)) }
        #expect(try await store.read(key(3)) == pcm(3))
        #expect(try await store.read(key(2)) == pcm(2))
        #expect(codec.decodes == 0)
        #expect(try await store.read(key(1)) == pcm(1))                   // evicted from memory: the base serves it
        #expect(codec.decodes == 1)
    }

    @Test func theBaseStoreStaysTheTruth() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 1_000_000)
        let store = RecentAudioStore(base: base, keeping: 4)
        try await store.write(pcm(1), for: key(1))
        await base.remove(key(1))                                          // evicted behind the tier's back
        #expect(!(await store.contains(key(1))))
        #expect(try await store.read(key(1)) == nil)
        try await store.write(pcm(2), for: key(2))
        try await store.remove(key(2))
        #expect(try await store.read(key(2)) == nil)
        #expect(codec.decodes == 0)
    }

    @Test func aFailedWriteCachesNothing() async throws {
        let codec = CountingCodec()
        let base = InMemoryAudioStore(codec: codec, capacityBytes: 100)   // 400 B of samples never fit
        let store = RecentAudioStore(base: base, keeping: 4)
        await #expect(throws: AudioStoreError.self) { try await store.write(pcm(1), for: key(1)) }
        #expect(try await store.read(key(1)) == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd .worktrees/plan-13-first-sound && swift test --filter "RenderKeyTests|AudioStoreTests|RecentAudioStoreTests" 2>&1 | tail -8`
Expected: compile errors for `contains([…])` and `RecentAudioStore`; `digestIsPinned` must PASS
already (it pins today's value — if it does not, stop: the material or separator differs from what the
plan assumed, and the pinned string must be corrected from a run of the current code, not the code
changed to match).

- [ ] **Step 3: The batch `contains` and the default**

In `Sources/T2SCore/Render/AudioStore.swift`, the protocol gains one requirement after `contains(_:)`:

```swift
    /// `contains` for many keys in one hop, in order. The coordinator asks about every rendered
    /// utterance of a document when it loads; one call, not one per utterance.
    func contains(_ keys: [RenderKey]) async -> [Bool]
```

and, after the protocol, a default so every conforming type outside this module still compiles:

```swift
public extension AudioStore {
    func contains(_ keys: [RenderKey]) async -> [Bool] {
        var out: [Bool] = []
        out.reserveCapacity(keys.count)
        for key in keys { out.append(await contains(key)) }
        return out
    }
}
```

In `FileAudioStore`, after `contains(_ key:)`:

```swift
    public func contains(_ keys: [RenderKey]) -> [Bool] {
        ensureIndexed()
        return keys.map { lru.sizes[$0] != nil }
    }
```

In `InMemoryAudioStore`, after `contains(_ key:)`:

```swift
    public func contains(_ keys: [RenderKey]) -> [Bool] { keys.map { blobs[$0] != nil } }
```

- [ ] **Step 4: The memory tier**

Create `Sources/T2SCore/Render/RecentAudioStore.swift`:

```swift
import Foundation

/// The last few renders, in memory, in front of a persistent store.
///
/// The scheduler writes every utterance to the AAC cache and the coordinator reads it back to play
/// it — through a temporary file each way — so every second heard was the cache, never the render
/// (`docs/superpowers/specs/2026-09-08-performance-audit.md` §3.3). This tier keeps the PCM of the
/// last `limit` writes (~1 MB each for 10 s at 24 kHz mono float) and serves a read from memory when
/// the base store still holds the key. The base store stays the truth: `contains`, `stats`, capacity
/// and eviction are its; a key the base has dropped is dropped here on the next read; a write the
/// base refuses is never remembered.
public actor RecentAudioStore: AudioStore {
    private let base: any AudioStore
    private let limit: Int
    private var recent: [RenderKey: PCMAudio] = [:]
    /// Oldest first.
    private var order: [RenderKey] = []

    public init(base: any AudioStore, keeping limit: Int = 8) {
        self.base = base
        self.limit = max(1, limit)
    }

    public func contains(_ key: RenderKey) async -> Bool { await base.contains(key) }

    public func contains(_ keys: [RenderKey]) async -> [Bool] { await base.contains(keys) }

    public func write(_ pcm: PCMAudio, for key: RenderKey) async throws {
        try await base.write(pcm, for: key)
        remember(key, pcm)
    }

    public func read(_ key: RenderKey) async throws -> PCMAudio? {
        if let pcm = recent[key] {
            if await base.contains(key) { return pcm }
            forget(key)
        }
        return try await base.read(key)
    }

    public func remove(_ key: RenderKey) async throws {
        forget(key)
        try await base.remove(key)
    }

    public func stats() async -> AudioStoreStats { await base.stats() }

    public func setCapacity(bytes: Int) async { await base.setCapacity(bytes: bytes) }

    private func remember(_ key: RenderKey, _ pcm: PCMAudio) {
        forget(key)
        recent[key] = pcm
        order.append(key)
        while order.count > limit {
            let oldest = order.removeFirst()
            recent[oldest] = nil
        }
    }

    private func forget(_ key: RenderKey) {
        guard recent.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }
}
```

- [ ] **Step 5: The cheaper hex**

In `Sources/T2SCore/Render/RenderKey.swift`, replace

```swift
        let digest = SHA256.hash(data: Data(material.utf8))
        rawValue = digest.map { String(format: "%02x", $0) }.joined()
```
with
```swift
        let digest = SHA256.hash(data: Data(material.utf8))
        // Lower-case hex by table: `String(format: "%02x")` per byte was most of the cost of the
        // thousands of keys a document load builds on the main actor (audit §5.4).
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in digest {
            hex.append(Self.hexDigits[Int(byte >> 4)])
            hex.append(Self.hexDigits[Int(byte & 0x0F)])
        }
        rawValue = String(decoding: hex, as: UTF8.self)
```
and add inside the struct:

```swift
    private static let hexDigits = Array("0123456789abcdef".utf8)
```

- [ ] **Step 6: Run the three suites to see them pass**

Run: `swift test --filter "RenderKeyTests|AudioStoreTests|RecentAudioStoreTests" 2>&1 | tail -5`
Expected: all pass, `digestIsPinned` included.

- [ ] **Step 7: One hop for the reconcile, none for a mismatched reference**

In `Sources/T2SAudio/PlaybackCoordinator.swift`, `reconcileWithStore()` currently loops with one
`await store.contains(...)` per candidate. Replace its body:

```swift
    private func reconcileWithStore() {
        let staleCandidates = rendered.indices.filter { rendered[$0] }
        guard !staleCandidates.isEmpty else { return }
        let store = self.store
        chain {
            // One hop for the whole document, not one per rendered utterance (audit §5.4).
            let keyed = staleCandidates.compactMap { i -> (index: Int, key: RenderKey)? in
                guard let ref = self.timeline?[utterance: i].audioRef else { return nil }
                return (i, RenderKey(rawValue: ref))
            }
            let present = await store.contains(keyed.map(\.key))
            var flipped = false
            for (entry, isPresent) in zip(keyed, present) where !isPresent {
                self.rendered[entry.index] = false
                self.timeline?[utterance: entry.index].audioRef = nil
                flipped = true
            }
            if flipped { self.replan() }
        }
    }
```

In `Sources/T2SApp/Playback/PrepareRunner.swift`, `loadDocuments`, the per-utterance loop

```swift
            for index in snapshot.rendered.indices {
                let expected = renderKey(documentID: id, utteranceIndex: index, voiceID: voiceID, timeline: timeline)
                let hasExpectedReference = timeline[utterance: index].audioRef == expected.rawValue
                let existsInCache = await audioStore.contains(expected)
                if !hasExpectedReference || !existsInCache {
                    snapshot.rendered[index] = false
                }
            }
```
becomes
```swift
            // Only an utterance whose reference already matches can be rendered; those are checked
            // against the store in one hop, the rest are unrendered without asking (audit §5.4).
            var candidates: [(index: Int, key: RenderKey)] = []
            for index in snapshot.rendered.indices {
                let expected = renderKey(documentID: id, utteranceIndex: index, voiceID: voiceID, timeline: timeline)
                if timeline[utterance: index].audioRef == expected.rawValue {
                    candidates.append((index, expected))
                } else {
                    snapshot.rendered[index] = false
                }
            }
            let present = await audioStore.contains(candidates.map(\.key))
            for (candidate, isPresent) in zip(candidates, present) where !isPresent {
                snapshot.rendered[candidate.index] = false
            }
```

- [ ] **Step 8: Put the tier in front of the app's store**

In `App/T2SReader/Shared/SharedLibraryFactory.swift`, the tuple's `audioStore: FileAudioStore` becomes
`audioStore: any AudioStore`, and

```swift
        let audioStore = FileAudioStore(directory: paths.audioDirectory, codec: AACCodec(), capacityBytes: capacityBytes)
```
becomes
```swift
        // The last few renders stay in memory so the live path plays the render, not the AAC cache
        // read back through a temporary file (audit §3.3); the file store stays the truth.
        let audioStore: any AudioStore = RecentAudioStore(
            base: FileAudioStore(directory: paths.audioDirectory, codec: AACCodec(), capacityBytes: capacityBytes)
        )
```

In `App/T2SReader/AppEnvironment.swift`, `let audioStore: FileAudioStore` becomes
`let audioStore: any AudioStore`, and the `init` parameter `audioStore: FileAudioStore` becomes
`audioStore: any AudioStore`. Then grep the app for any other `FileAudioStore`-typed use:

Run: `grep -rn "FileAudioStore" App/ Sources/T2SApp | grep -v "^Sources/T2SCore"`
Expected: only the construction in `SharedLibraryFactory.swift`. Fix any other typed use to `any AudioStore`
(`StorageModel`, `DeviceMonitor` take `any AudioStore` already — confirm with the grep).

- [ ] **Step 9: Build the app, run the whole suite, commit**

Run: `scripts/build-app.sh 2>&1 | tail -3` — expected `** BUILD SUCCEEDED **`.
Run: `swift test 2>&1 | tail -3` — expected: every test passes.

```bash
git add Sources/T2SCore/Render Sources/T2SAudio/PlaybackCoordinator.swift Sources/T2SApp/Playback/PrepareRunner.swift App/T2SReader/Shared/SharedLibraryFactory.swift App/T2SReader/AppEnvironment.swift Tests/T2SCoreTests/Render
git commit -m "Plan 13 Task 4: the live path plays the render — a memory tier in front of the AAC cache, one store hop per document load, hex without String(format:)"
```

---

### Task 5: Prepare writes a chapter once

**Files:**
- Modify: `Sources/T2SApp/Playback/PrepareRunner.swift` — `render(_:document:)` (~lines 200-245), a new `chapterWriteInterval` and `chapterWrites`
- Test: `Tests/T2SAppTests/PrepareRunnerTests.swift`

**Interfaces:**
- Consumes: `LibraryStore.saveChapter(_:at:of:)`, `TimeSource.now()` (the runner already holds `timeSource`).
- Produces: `PrepareRunner.chapterWriteInterval: TimeInterval` (public var, default 10);
  `PrepareRunner.chapterWrites: Int` (internal, `private(set)`, test-only observability).

- [ ] **Step 1: Write the failing test**

In `Tests/T2SAppTests/PrepareRunnerTests.swift`, add:

```swift
    /// Every `.rendered` event used to re-encode and rewrite the whole chapter blob — 100–300× write
    /// amplification for a 3 h prepare (audit §5.2). Now a chapter is written when the pass moves to
    /// another chapter, when `chapterWriteInterval` has elapsed, and at the end.
    @Test func aChapterIsWrittenOnceNotPerUtterance() async throws {
        let fixtures = try AppFixtures(readers: [FakeReader(chapterCount: 1)])   // one chapter, two utterances
        let id = try await fixtures.importFake()
        let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let clock = ManualTimeSource()                                            // never advances: no interval flush
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: FakeEngine(secondsPerCharacter: 0.05), defaults: defaults,
                                   arbiter: RenderArbiter(), timeSource: clock)

        let result = await runner.run(lastPlayed: id, queue: [id],
                                      device: DeviceState(charging: true, thermalSerious: false,
                                                          lowPowerMode: false, storeFull: false))

        #expect(result.renderedUtterances == 2)
        #expect(runner.chapterWrites == 1)
        let stored = try #require(try await fixtures.store.timeline(for: id)).timeline
        #expect(stored.chapters[0].utterances.allSatisfy { $0.audioRef != nil && $0.duration.isActual })
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd .worktrees/plan-13-first-sound && swift test --filter PrepareRunnerTests 2>&1 | tail -5`
Expected: `value of type 'PrepareRunner' has no member 'chapterWrites'`.

- [ ] **Step 3: Coalesce the writes**

In `Sources/T2SApp/Playback/PrepareRunner.swift`, after `public var voiceRouting: …`, add:

```swift
    /// How long a chapter's rendered metadata may sit unwritten while the pass stays in that chapter.
    /// Rendered audio is already on disk under its key; a lost write self-heals on the next load
    /// (`PlaybackCoordinator.reconcileWithStore`), so this bounds a crash's loss, not correctness.
    public var chapterWriteInterval: TimeInterval = 10
    /// Chapter blobs written by this runner. Internal for one test: coalesced and per-utterance
    /// writes produce the same timeline, minutes of flash I/O apart.
    private(set) var chapterWrites = 0
```

Replace the body of `render(_ jobs:document:)` from `var timeline = document.timeline` to the end of the
function with:

```swift
        var timeline = document.timeline
        var outcome = GroupResult()
        var dirtyChapters: Set<Int> = []
        var lastWrite = timeSource.now()

        func flush() async {
            for chapterIndex in dirtyChapters.sorted() {
                do {
                    try await store.saveChapter(timeline.chapters[chapterIndex], at: chapterIndex, of: document.id)
                    chapterWrites += 1
                } catch {
                    lastError = "\(error)"
                }
            }
            dirtyChapters.removeAll()
            lastWrite = timeSource.now()
        }

        for await event in scheduler.events {
            if Task.isCancelled, !cancelRequested { cancel() }
            switch event {
            case .rendered(let rendered):
                guard rendered.documentID == document.id,
                      let chapterIndex = timeline.chapterIndex(forUtterance: rendered.utteranceIndex)
                else { continue }

                var utterance = timeline[utterance: rendered.utteranceIndex]
                let useNewTimings = !rendered.wordTimings.isEmpty || (utterance.wordTimings ?? []).isEmpty
                let changed = utterance.audioRef != rendered.key.rawValue
                    || utterance.duration != .actual(rendered.duration)
                    || (useNewTimings && utterance.wordTimings != rendered.wordTimings)
                guard changed else { continue }

                utterance.audioRef = rendered.key.rawValue
                utterance.duration = .actual(rendered.duration)
                if useNewTimings { utterance.wordTimings = rendered.wordTimings }
                timeline[utterance: rendered.utteranceIndex] = utterance
                outcome.renderedUtterances += 1
                outcome.preparedSeconds += rendered.duration

                // Write when the pass leaves a chapter, or when the interval has passed inside one —
                // never per utterance (audit §5.2).
                let movedToAnotherChapter = !dirtyChapters.isEmpty && !dirtyChapters.contains(chapterIndex)
                dirtyChapters.insert(chapterIndex)
                if movedToAnotherChapter || timeSource.now() - lastWrite >= chapterWriteInterval {
                    await flush()
                }
            case .failed(_, _, let message):
                lastError = message
            case .storeFull:
                outcome.storageFull = true
                await scheduler.cancel()
            case .idle:
                await flush()
                currentScheduler = nil
                return outcome
            }
        }
        await flush()
        currentScheduler = nil
        return outcome
```

(`renderedUtterances`/`preparedSeconds` now count the in-memory update; a failed flush sets
`lastError`, as a failed save did before.)

- [ ] **Step 4: Run the suite and commit**

Run: `swift test --filter PrepareRunnerTests 2>&1 | tail -5` — expected: all pass.
Run: `swift test 2>&1 | tail -3` — expected: every test passes.

```bash
git add Sources/T2SApp/Playback/PrepareRunner.swift Tests/T2SAppTests/PrepareRunnerTests.swift
git commit -m "Plan 13 Task 5: Prepare writes a chapter once — on leaving it, every 10 s inside it, and at the end; not per utterance"
```

---

### Task 6: The rate steps down before playback stalls

**Files:**
- Modify: `Sources/T2SAudio/PlaybackCoordinator.swift` — a new `rateLoweredTo`, `apply(_:)`'s `.rendered` and `.idle` cases (~lines 370-403), `setRate`
- Test: `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`

**Interfaces:**
- Consumes: `RenderScheduler.measuredRTF`, `RateLimits.maxSustainableRate(rtf:)`, `RateLimits.availableRates(rtf:)`, `AudioPlaying.rate`.
- Produces: `PlaybackCoordinator.rateLoweredTo: Double?` (published, `private(set)`; nil until a
  lowering, cleared by `setRate` and `load`).

- [ ] **Step 1: Write the failing test**

In `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`, after `rateIsClampedBySustainability`, add:

```swift
    /// Spec §3.6 gates the rates *offered*; a rate chosen while the RTF was unknown, or a phone that
    /// throttles mid-book, still left the current rate in place until the window drained and playback
    /// paused on "catching up" (audit §3.5). Now the rate follows the cap down, and says so once.
    @Test func rateStepsDownWhenTheMeasuredRTFCannotSustainIt() async throws {
        let block = SourceBlock(text: "Alpha one. Beta two. Gamma three.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let timeline = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                             segmenter: Segmenter(normalizer: TextNormalizer()))
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.5, timeSource: clock)   // 0.5 sustains 1.5x, not 3x
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let player = FakePlayer()
        let c = PlaybackCoordinator(engine: engine, store: store, player: player, playheadStore: MemoryPlayheadStore(), timeSource: clock,
                                    configuration: CoordinatorConfiguration(windowSeconds: 60, primeSeconds: 30, prepareBudgetSeconds: 300, queuedSegments: 2))
        c.load(Document(title: "T", sourceType: .article), timeline: timeline)
        c.setRate(3.0)                                                   // RTF unknown: allowed
        #expect(c.rate == 3.0 && c.rateLoweredTo == nil)

        await c.waitForRenderIdle()                                      // three renders at RTF 0.5

        #expect(c.measuredRTF == 0.5)
        #expect(c.availableRates == [0.5, 0.75, 1.0, 1.25, 1.5])
        #expect(c.rate == 1.5 && player.rate == 1.5)
        #expect(c.rateLoweredTo == 1.5)
        c.setRate(1.0)
        #expect(c.rateLoweredTo == nil)                                  // the listener's own choice clears the notice
    }
```

- [ ] **Step 2: Run it to see it fail to compile**

Run: `cd .worktrees/plan-13-first-sound && swift test --filter PlaybackCoordinatorTests 2>&1 | tail -5`
Expected: `value of type 'PlaybackCoordinator' has no member 'rateLoweredTo'`.

- [ ] **Step 3: Follow the cap down**

In `PlaybackCoordinator`, after `public private(set) var measuredRTF: Double?`, add:

```swift
    /// Set when the measured RTF made the current rate unsustainable and the coordinator lowered it
    /// (spec §3.6: never offered-then-stuttering; audit §3.5: never left in place until "catching
    /// up"). The Reader shows it once; `setRate` — the listener's own choice — and `load` clear it.
    public private(set) var rateLoweredTo: Double?
```

In `load(_:timeline:)`, after `lastRenderError = nil`, add `rateLoweredTo = nil`.

In `setRate(_:)`, after `rate = clamped`, add `rateLoweredTo = nil`.

Add a private method after `replan()`:

```swift
    /// Re-reads the scheduler's rolling RTF and, when the current rate is no longer sustainable,
    /// steps it down to the highest rate that is — a smaller window replans from here.
    private func refreshRates() async {
        measuredRTF = await scheduler.measuredRTF
        availableRates = RateLimits.availableRates(rtf: measuredRTF)
        let cap = RateLimits.maxSustainableRate(rtf: measuredRTF)
        guard rate > cap + 1e-9 else { return }
        rate = cap
        player.rate = cap
        rateLoweredTo = cap
        replan()
    }
```

In `apply(_:)`, the `.idle` case's chained work

```swift
            chain {
                self.measuredRTF = await scheduler.measuredRTF
                self.availableRates = RateLimits.availableRates(rtf: self.measuredRTF)
            }
```
becomes
```swift
            chain { await self.refreshRates() }
```
(and drop the now-unused `let scheduler = self.scheduler` line above it). In the `.rendered` case,
after `refreshHighlight()` and before the `if awaitingIndex == r.utteranceIndex {` block, add:

```swift
            // The RTF moves with every render, and a throttling phone shows it here first (§3.6).
            chain { await self.refreshRates() }
```

- [ ] **Step 4: Run the coordinator tests, then everything**

Run: `swift test --filter PlaybackCoordinatorTests 2>&1 | tail -5` — expected: all pass (the existing
`rateIsClampedBySustainability` included: no render has finished there, so nothing is lowered).
Run: `swift test 2>&1 | tail -3` — expected: every test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/PlaybackCoordinator.swift Tests/T2SAudioTests/PlaybackCoordinatorTests.swift
git commit -m "Plan 13 Task 6: the rate follows the measured RTF down — a throttling phone lowers the rate instead of draining the window into catching up"
```

---

### Task 7: Docs and the ledger

**Files:**
- Modify: `docs/HANDOFF.md` (a "Resume here (2026-09-08) — Plan 13" section above the Plan 12/11 ones; the `_Last updated_` line)
- Modify: `docs/superpowers/specs/2026-09-08-performance-audit.md` (a "Progress" note under §2)
- Modify: `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (§3.4.1 tier-2 row; rev 13 changelog entry)

- [ ] **Step 1: The spec**

In `docs/superpowers/specs/2026-09-01-t2s-reader-design.md`, the tier table row

```
| 2 **Prime** | The first ~30 s of audio of a newly imported document | Immediately on import | After play-ahead |
```
becomes
```
| 2 **Prime** | The first ~30 s of audio from a document's resume position: a new import from its start, the continue-document from where the reader left it (rev 13) | On import; at launch | After play-ahead |
```

Under `## 11. Changelog`, above the `**rev 12 (2026-09-08)**` entry, add:

```
**rev 13 (2026-09-08)** — Plan 13: first sound
- **§3.4.1** the prime tier is planned at last — after an import and at launch for the
  continue-document, from the resume index; it had existed in `RenderPolicy` since Plan 2 with no
  caller. The rendered-audio cache gains a memory tier for the last few renders (`RecentAudioStore`)
  so the live path plays the render (§3.3 of the performance audit).
- **§3.6** a rate the measured RTF can no longer sustain is lowered to the highest one it can,
  and the coordinator says so (`rateLoweredTo`), instead of the window draining into "catching up".
```

If the document's header carries a revision line (grep `^_rev` or `rev 12` near the top), bump it to rev 13.

- [ ] **Step 2: The audit's progress note**

In `docs/superpowers/specs/2026-09-08-performance-audit.md`, directly under the `## 2. Ranked
recommendations` heading and its effort legend (before the table), add:

```
**Progress (Plan 13, 2026-09-08):** #1 done (Release on the Phone scheme); #3 done (G2P in the
warm-up, prime after import and at launch); #4 done as `RecentAudioStore` (the temp-file encode and
decode paths stay); #5 partly (one store hop per load, cheaper keys — the `play()` gate and
`LibraryModel.refresh` remain); #8 done; #11 done (`rateLoweredTo`; the Reader's line is the UI
plan's). Open: #2, #6, #7, #9, #10, #12, #13, #14.
```

- [ ] **Step 3: HANDOFF**

In `docs/HANDOFF.md`, change the `_Last updated …_` line to begin
`_Last updated 2026-09-08 (Plan 13 — first sound — on \`plan-13-first-sound\`, in the worktree …` and
add, above the "Performance audit (2026-09-08)" section:

```
## Resume here (2026-09-08) — Plan 13

The owner said "you decide" after the performance audit; Plan 13
(`docs/superpowers/plans/2026-09-08-plan-13-first-sound.md`, branch `plan-13-first-sound` off `dev`
@ b951d86, worktree `.worktrees/plan-13-first-sound`) took the audit's single-task items while
another session ran Plan 12 (the Player sheet retired) in the main checkout:

- **Task 1** — the Phone scheme's Run action is Release (`App/project.yml`); the install recipe below
  no longer needs the by-hand flip. Every listen before this may have been `-Onone`.
- **Task 2** — `KokoroCoreMLEngine.load()` builds the American G2P after the stages, so the launch
  warm-up pays it, not the first sentence.
- **Task 3** — the prime tier runs: `RenderPolicy` primes from the resume index;
  `PrepareRunner.prime(_:)` after every import (`ImportModel.afterImport`, wired in `AppEnvironment`)
  and `primeContinueDocument()` from `T2SReaderApp`'s scene task at launch.
- **Task 4** — `RecentAudioStore` keeps the last eight renders in memory in front of `FileAudioStore`
  (`SharedLibraryFactory`); `AudioStore.contains(_ keys:)` makes the coordinator's and Prepare's
  reconcile one hop; `RenderKey` hexes by table.
- **Task 5** — Prepare writes a chapter when it leaves it, every 10 s inside it, and at the end.
- **Task 6** — `PlaybackCoordinator.refreshRates()` on every render: a rate above the sustainable cap
  steps down and `rateLoweredTo` is set for the Reader to show (deferred to the UI plan).

**The phone listen.** Install with the Phone scheme (Release now). Listen for: a new import's first
tap starting at once; the mini-player's first tap after a launch starting at once; a book that has
never been played starting within ~2–3 s (that wait is Plan 14's — streaming the first sound).

**Next (Plan 14):** streaming the head utterance's first piece to the player — audit #2 — with the
quality probe on the seam a short first piece makes. Then the open path's `play()` gate and
`LibraryModel.refresh` (#5), and, once the UI plan has merged, the tick churn (#7).
```

- [ ] **Step 4: Commit and the whole suite one last time**

Run: `cd .worktrees/plan-13-first-sound && swift test 2>&1 | tail -3` — expected: every test passes.

```bash
git add docs/
git commit -m "Plan 13 Task 7: docs — HANDOFF resume section, the audit's progress note, spec §3.4.1 and rev 13"
```

Then, from the **main folder** (never from inside the worktree — the guard blocks `git -C`):

```bash
git merge --ff-only plan-13-first-sound   # from dev — if dev has moved, rebase the branch onto dev first, in the worktree
git push origin dev
git worktree remove .worktrees/plan-13-first-sound && git branch -d plan-13-first-sound
```

If the main checkout is still on the other session's branch when the plan finishes, do not switch it:
merge through a temporary worktree on `dev` as the audit commit was (`git worktree add <tmp> dev`,
`git merge --ff-only plan-13-first-sound`, `git push origin dev`, `git worktree remove <tmp>`).
