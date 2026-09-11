# Plan 18 — Render ahead by chapter while in front; the background loop only tops up

_2026-09-11. Branch `render-ahead-by-chapter` off `dev` @ 869fe6b (a worktree, as Plan 17 did; `git status` shows nothing of another session's outside `.claude/`). Root package logic first, app wiring last; every step lands with `swift test`. Nothing here touches `Packages/T2SKokoro`._

**Goal.** On 2026-09-10 the 11 Pro, locked during playback, ran dry once a minute: the `CPUBudget` renders ~70 s of audio in a ~14 s burst and then sleeps ~60 s (crashreport.md Finding 2b, table at lines 187–193), so the background loop sustains about 0.9 audio-seconds per wall-second at 1x — it can *hold* a buffer but never *grow* one, and at 1.5x it loses 0.6 s/s. `b5b34fa` widened the window to 180 s so one cycle's burstiness is absorbed. This plan makes the foreground — screen on, no budget, RTF 0.17 on the A13, 0.05 on the A19 GPU — build a buffer measured in chapters, persisted in the store it already writes to, so that after a lock the same loop finds its window already rendered and does almost nothing (research §"What this means" item 5; HANDOFF "Owed").

---

## 1. The pipeline as it is

**Units and representation.** A `Timeline` is `[Chapter]`, each `[Utterance]` (`Sources/T2SCore/Model/Timeline.swift:3-19`); utterances are addressed by one flat index across chapters (`utteranceRange(ofChapter:)` :36-40, `chapterIndex(forUtterance:)` :42-50). An `Utterance` carries `audioRef: String?` (the render key of its cached clip) and `duration: .estimated | .actual` (`Model/Utterance.swift:47-56`). `Timeline.isFullyRendered` (:84-86) is what the UI's `~` on totals reads.

**Keys and the cache.** `RenderKey` is SHA-256 of `documentID ⟂ utteranceIndex ⟂ voiceID ⟂ engineID ⟂ normalizerVersion ⟂ segmenterVersion` (`Render/RenderKey.swift:11-25`); a voice or engine change is structurally a new key. The store protocol is `AudioStore` (`Render/AudioStore.swift:20-33`) with a shared `LRUIndex` (:45-80). On the phone it is `RecentAudioStore(keeping: 8)` — the last eight PCM renders in memory (`Render/RecentAudioStore.swift:12-19`) — in front of `FileAudioStore`: one AAC file per key under `<cache>/<codec id>/` (`Render/FileAudioStore.swift:7-18`), recency = file mtime rebuilt on first use (:45-60), LRU eviction on write (:87), touched on read (:106). The codec is AAC 64 kbps mono 24 kHz ≈ 34 MB/hour measured, ≈ 0.5 MB/min (`Sources/T2SAudio/AACCodec.swift:5-9`). Cap: `AppPaths.defaultAudioCapacityBytes` = 2 GB (`Sources/T2SApp/Environment/AppPaths.swift:28`), user-settable 512 MB–4 GB (`Storage/StorageModel.swift:24-29`); "store full" for policy purposes is < 32 MB of headroom (`Environment/DeviceStateMapping.swift:28-35`).

**Policy (pure).** `RenderPolicy.plan(PolicyInput) -> [RenderJob]` (`Render/RenderPolicy.swift:99-148`). Tiers `playAhead = 0, prime, prepare, manual` (:3-7). One `walk(doc, from:, budget:, tier:)` (:107-119) emits a job for every *unrendered* utterance from `start` while the running sum of `seconds` (rendered or not) stays under `budget`, deduplicated through `seen`. Tier 1 walks the playing document from the playhead with budget `windowSeconds × rate` (:121-124). Tier 3 walks `lastPlayed` then the queue from `resumeIndex` for `prepareBudgetSeconds` (3 h) but only when `charging && !thermalSerious && !lowPowerMode && !storeFull` (:130-140). The snapshot the policy sees is `RenderSnapshot { seconds: [TimeInterval], rendered: [Bool], resumeIndex }` (:20-43) — it has **no chapter boundaries**.

**Scheduler.** `RenderScheduler` (`Render/RenderScheduler.swift:53`) executes one plan serially; `setPlan` *replaces* everything pending (:104-118), the request in flight finishes. Per request (:157-208): a cache hit yields `.rendered` with empty word timings and no synthesis (:158-162); otherwise, if a `CPUBudget` was given, `waitForHeadroom` first (:167-169), then synthesize, `record()` the CPU sample (:180), write to the store (:187), yield `.rendered`. Tiers matter only at `arbiter.acquire(request.job.tier)` (:147).

**The lease.** `RenderArbiter` is one lease shared by the coordinator's scheduler and `PrepareRunner`'s; ownership changes only between utterances. `release()` hands the lease to the lowest waiting tier — by iterating a **hard-coded list** `[.playAhead, .prime, .prepare, .manual]` (`Render/RenderArbiter.swift:22`). A tier not in that list would wait forever.

**The budget and the gate.** `ForegroundGate` is the one fact iOS's rules turn on (`Render/ForegroundGate.swift:15-62`); `RootPager` sets it from `scenePhase` (`App/T2SReader/Root/RootPager.swift:208-210`). `CPUBudget(gate:)` defaults to 36 CPU-seconds per trailing 60 s (`Render/CPUBudget.swift:32-43`); `waitForHeadroom` returns at once in front (:82) and sleeps in 1–5 s slices behind (:92-95); `record()` after every render (:71-73, `abb3875`) keeps the window's floor current. One budget instance is shared by the coordinator and Prepare (`App/T2SReader/AppEnvironment.swift:141,156-159,85-86`).

**Coordinator.** `PlaybackCoordinator` (`Sources/T2SAudio/PlaybackCoordinator.swift`) owns `rendered: [Bool]` (:64). `load()` seeds it from `audioRef == expected key` (:126-139) and `reconcileWithStore()` flips any entry the store has since evicted (:192-212). `replan()` (:422-450) builds the `PolicyInput` — `PlayingState` is passed **whenever a document is loaded, paused or not** (:426), `primes: []` (:427), `windowSeconds` from `configuration` (:429) — and submits; it runs on `load`, `seek`, `setRate`, `device` and `queue` `didSet` (:54,56), every `segmentFinished` (:407), and `play()` only when nothing is queued (:226). `apply(.rendered)` writes `audioRef`, `duration = .actual`, marks the chapter changed, sets `rendered[i] = true`, rebuilds `TimeIndex` (:495-521). `CoordinatorConfiguration.windowSeconds` defaults to 60 (:9-23); the app sets it to `KokoroComposition.playAheadWindowSeconds` = 180 on the CPU path, 600 on the GPU path (`App/T2SReader/System/KokoroComposition.swift:355`, `AppEnvironment.swift:152-155`). The coordinator does not know the foreground from the background.

**Persistence of the metadata.** `PlayerModel.persistRenderedChapters()` writes the chapters the coordinator marked changed (`Sources/T2SApp/Player/PlayerModel.swift:328-350`, merging stored word timings :357-368), on pause (:246-253), on load of another document (:198), and — the lock path — from `RootPager`'s `.background` handler under a `UIBackgroundTask` (:218-231, :330-340). The audio itself is on disk the moment `store.write` returns.

**Prepare.** `PrepareRunner` (`Sources/T2SApp/Playback/PrepareRunner.swift`) builds its own `RenderScheduler` per group (:290) with the same arbiter and budget, writes chapter blobs on leaving a chapter or every `chapterWriteInterval` = 10 s (:70, :345-351). It runs only on a charger (`isSafe` :401-403), never while playing (`RootPager.swift:196-204` cancels it), and from a `BGProcessingTask` with `requiresExternalPower` (`App/T2SReader/System/PrepareTask.swift:42-46`).

**The engine's foreground/background split.** `KokoroCoreMLEngine.renderSet` (`Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift:610-618`) consults placement only when `backgroundComputeUnits != nil`; on the CPU path that is nil (`KokoroComposition.swift:249`), so the A13 renders on its main set in every state and nothing in the engine waits on the gate during playback. `waitWhileThermallySerious` (:600-605) guards background-set loads only.

**What the reader sees today.** The scrubber's ticks mark the render frontier — rendered `ink2`, unrendered `ink3` (`Sources/T2SApp/Player/ScrubberModel.swift:33-56`, `App/T2SReader/Reader/ThinScrubber.swift:8`); "catching up…" on the time row (`App/T2SReader/Reader/ReaderPage.swift:199-203`) and the spinner in the play button (`ReaderControls.swift:37-41`) when the frontier is reached.

**A precedent already in the code.** On a charger, the coordinator's own plan includes tier 3 for the *current* document from the playhead for three hours, in front and behind (`RenderPolicy.swift:130-140` with `lastPlayed = document.id`, `PlaybackCoordinator.swift:427`). The foreground fill below is that walk with a different guard (frontmost and listening, not charging) and a smaller, chapter-shaped bound.

---

## 2. Design

### 2.1 What "a chapter ahead" means

- **Unit:** the utterance, as everywhere. The store is keyed per utterance; a fill interrupted at any point loses nothing (spec §3.4.1).
- **Bound:** seconds of audio at 1x ahead of the playhead, `clamp(secondsToEndOfCurrentChapter, min...max)`:
  - CPU path (A13): **600…1800 s** (10–30 min). 30 min at RTF 0.17–0.56 is 5–17 min of CPU; ≈ 17 MB on disk.
  - GPU path (A19): **1200…3600 s**. 60 min at RTF 0.05 is 3 min of GPU; ≈ 34 MB.
  - Everyday build (no Kokoro): off. `CoordinatorConfiguration.foregroundFill` defaults to nil, so every existing test and the system-voice path are unchanged.
- **Why the chapter is the rounding unit, not the hard bound:** a pasted article or a PDF is one chapter (`Library.swift:169-175` builds chapters as the reader gave them), so "the chapter" alone is unbounded; a book of three-minute chapters would under-fill. With the clamp, a 20-min chapter renders to its end; a 2-min remainder is topped up to 10 min into the next chapter ("next chapter only when idle" is then simply plan order — the walk is in index order and the current chapter's utterances come first); a 60-min chapter or article stops at 30.
- **Not rate-scaled.** The window is in playback-seconds because it is a time-to-dry; the fill is a CPU/disk spend, so it is 1x audio seconds. Drain arithmetic for the plan's own record: background production ≈ 0.9 s/s. At 1x a 180 s window lasts ~30 min after a lock and a 20-min fill ~3 h; at 1.5x (deficit 0.6 s/s) 180 s lasts 5 min, 20 min lasts ~33 min; at 2x (deficit 1.1) 30 min lasts ~27 min.

### 2.2 Where it runs, and the tier

- **A new tier `RenderTier.chapterAhead`, ranked after `prime` and before `prepare`** (`case playAhead = 0, prime, chapterAhead, prepare, manual`). Reasons: the window must always win the next boundary; a prime (an import during playback, `AppEnvironment.swift:104-108`) must not wait ten minutes behind a fill — at `.playAhead` it would, because `release()` picks the lowest tier and the coordinator would re-acquire at every utterance; and the fill should beat Prepare, which on a charger plans the same utterances (dedup via `seen`).
- **`RenderArbiter.release()` must learn the tier.** Make `RenderTier: CaseIterable` and iterate `allCases` (declaration order is priority order) instead of the literal list at `RenderArbiter.swift:22`, so this cannot be forgotten again. Nothing persists a tier's raw value (grep confirmed).
- **The foreground signal** is a new `PlaybackCoordinator.isForeground: Bool { didSet { replan() } }`, exactly the `device`/`queue` pattern (:54,56), set by `RootPager` on the same line that sets the gate (:208-210). The policy stays free of "foreground": `PolicyInput` gains `foregroundFill: ClosedRange<TimeInterval>?` and the coordinator passes `configuration.foregroundFill` only when `isForeground && (state == .playing || state == .catchingUp)`, else nil.
- **Only while listening**, not merely loaded: opening the Reader to look at chapters must not cost ten minutes of CPU. (Alternative — fill whenever loaded in front, like the window does at :426 — is one condition; see open question 1.) Because `play()` sets `state = .playing` after `fill()` without a replan (:229-230) and `pause()` never replans (:233-239), both get a `replan()` so the fill starts on play and stops on pause; the in-flight utterance finishes.
- **Guards** in the policy, table-testable: no fill under `thermalSerious`, `lowPowerMode` or `storeFull` (the Prepare guards minus charging); the window is never affected. Charging changes nothing — tier 3 already renders three hours in that state.

### 2.3 Where the audio lives; eviction

In the existing `FileAudioStore`, same keys, same codec. Nothing new is held in memory: the engine renders one utterance, the scheduler encodes and writes it, the PCM is released; the `RecentAudioStore` keeps its eight most recent (≈ 8 MB). Eviction is the existing LRU by mtime: clips *behind* the playhead are older than the fill's, so they go first; the `storeFull` guard stops the fill 32 MB before the cap. A fill of the default bound is 1–2 % of the 512 MB option.

### 2.4 How the background loop discovers what is rendered

Nothing new. Within the process, every `.rendered` from the fill lands in `rendered[i] = true` (`PlaybackCoordinator.swift:508`), so when `isForeground` flips false the `didSet` replan produces today's plan exactly — the 180 s window — whose walk emits jobs only for unrendered utterances: while the playhead is inside the fill the plan is empty and the loop idles at zero CPU; near the fill's end it tops up at the budget's pace. Across a relaunch: `audioRef`s are persisted by the `.background` handler on lock; `load()` seeds `rendered` from them and `reconcileWithStore` checks the store; and even an unpersisted ref self-heals as a scheduler cache hit (:158-162) at the cost of one decode and its word timings (mitigation: optional Step 7).

### 2.5 The 180 s window and the `CPUBudget`

Untouched. In front the budget never waits; the plan is window + fill. Behind, the plan is the window; the budget paces as before. The one interaction to know: after a full-CPU foreground minute the trailing window is saturated, so the *first* background render may sleep a whole window (≤ 60 s, `CPUBudget.swift:10-14`) — harmless now that the buffer is minutes deep, and `record()` after each render (:180) keeps it from being longer. If the app leaves the foreground with a fill job already past `arbiter.acquire`, that one job waits for headroom and renders — one extra utterance, which is a top-up anyway.

### 2.6 Thermal

v1 uses the plumbing that exists: `ProcessInfo.thermalStateDidChangeNotification` → `DeviceMonitor.refresh` (`DeviceMonitor.swift:28-35`) → `updatePrepareDeviceState` → `coordinator.device` (`RootPager.swift:311-318`) → `didSet { replan() }` → the fill's guard drops it at `.serious`; the window continues as today; recovery replans again. `.fair` is read by the monitor but collapsed by `DeviceStateMapping` — a follow-up (Step 8) can halve the bound there once the 11 Pro says whether a 10-minute fill reaches `.fair`. The screen's idle timer is not disabled for a fill (only the warm-up does that, `RootPager.swift:215-217`): auto-lock ends the fill; it is opportunistic.

### 2.7 Seek, voice change, relaunch

- **Seek:** `seek()` replans (:258) from the new playhead: window first, then the fill for the new chapter; the old chapter's pending jobs are dropped by `setPlan`; the utterance in flight finishes (≤ one 15 s bucket, 3–8 s of A13 CPU). Already-rendered clips anywhere stay in the store and in `rendered[]`.
- **Voice change:** `VoiceChangeModel.apply` (`Storage/VoiceChangeModel.swift:32-52`) evicts every clip and clears every ref before reloading paused — unchanged, since the key embeds the voice. `discardedSeconds` (:25-28) will simply report a larger number.
- **Relaunch:** §2.4. The launch prime (`App/T2SReader/T2SReaderApp.swift:38-57`) is unaffected; the fill begins at the first play in front.
- **Sleep timer / queue continuation:** the timer pauses → replan drops the fill; `QueueContinuation` loads the next document and plays → the fill starts there.

### 2.8 What the reader sees

No new UI in v1. The scrubber's frontier (`ScrubberModel.renderedTicks`) visibly runs ahead through the chapter, and `~` leaves the total sooner. Possible later: a "ready to the end of the chapter" state on the time row where "catching up…" lives — not now, a new line there flickers.

---

## 3. Risks and rollback

| Risk | Where it bites | Mitigation |
|---|---|---|
| Sustained CPU on the A13 with the screen on heats the phone | 5–17 min of full CPU per fill | Bound; `.serious` stops the fill; `.fair` follow-up; measure on the phone before raising the bound |
| Battery spent on audio never listened to | a listener who stops after five minutes | The bound; off in Low Power Mode; free on a charger |
| A prime starves behind a fill | an import while playing | The tier order and the `allCases` arbiter fix (Step 1) — **a tier missing from `release()` hangs forever** |
| Main-actor churn: ~1 `.rendered`/s on the A13 → a `TimeIndex` rebuild and a tick-cache miss each | `PlaybackCoordinator.swift:509`, `PlayerModel.swift:138-154` | The audit already budgeted per-render work; a Prepare pass in front does the same today; watch the 10 Hz body on the 11 Pro |
| `RecentAudioStore` no longer serves playback (clips heard were written minutes ago) | one AAC decode via temp file per utterance | Existing behaviour beyond eight renders; ms per clip; follow-up: a playhead-aware recent tier |
| The first background render after a lock waits ≤ 60 s | `CPUBudget` window saturated by the fill | Covered by the buffer; `record()` floor |
| Existing tests change shape | `PlaybackCoordinatorTests` fixtures | The configuration defaults to nil; nothing changes until Step 5 wires the app |

**Rollback.** Three independent switches, any one of which restores today's behaviour: (1) the developer default `render.foregroundFillMaxSeconds = 0` (mirrors `kokoro.computeUnits`, `KokoroComposition.swift:205`), no rebuild; (2) `foregroundFillSeconds: nil` in `KokoroComposition`; (3) `git revert` of the small commits — the new tier, the snapshot field and the config are inert when the range is nil. Audio a fill wrote is ordinary cache under ordinary keys; nothing to migrate or clean.

---

## 4. Steps

Each step is one commit; `swift test` after each. App-target steps are verified by reading and the owner's `scripts/build-app.sh`, as Plan 17 did.

### Step 1 — The tier, and an arbiter that cannot forget one
- `Sources/T2SCore/Render/RenderPolicy.swift:3-7`: `public enum RenderTier: Int, Hashable, Comparable, CaseIterable, Sendable { case playAhead = 0, prime, chapterAhead, prepare, manual }` with a doc line on the new case.
- `Sources/T2SCore/Render/RenderArbiter.swift:22`: `for tier in RenderTier.allCases` in place of the literal list.
- Tests, `Tests/T2SCoreTests/Render/RenderArbiterTests.swift` (pattern at :5-16): hold the lease as `.playAhead`; queue waiters at `.prepare`, `.chapterAhead`, `.prime`; three releases resume `prime`, `chapterAhead`, `prepare` in that order. `RenderPolicyTests`: `RenderTier.allCases == RenderTier.allCases.sorted()`.

### Step 2 — Chapter boundaries in the snapshot
- `RenderPolicy.swift:20-43`: `public var chapterStarts: [Int]` on `RenderSnapshot`; the array init takes `chapterStarts: [Int] = [0]`; the timeline init computes a running start per chapter. Add `func chapterEnd(containing i: Int) -> Int { chapterStarts.first { $0 > i } ?? seconds.count }` (tolerates empty chapters' duplicate starts). Callers (`PlaybackCoordinator.swift:424`, `Library.swift:174`, `RenderPolicyTests.swift:10`) compile unchanged.
- Tests in `RenderPolicyTests`: a timeline of chapters with 3, 4, 0, 2 utterances yields `[0, 3, 7, 7]`; `chapterEnd(containing: 4) == 7`, `(containing: 8) == 9`; the array init defaults to `[0]`.

### Step 3 — The policy's fill tier
- `RenderPolicy.swift`: `PolicyInput.foregroundFill: ClosedRange<TimeInterval>? = nil` (doc: "audio seconds at 1x from the playhead; nil renders only the window"). After tier 2 and before tier 3:
  ```swift
  // Tier 2b: the foreground fill — the rest of the playing document's chapter, clamped, in any
  // power state but not on a hot, low-power, or full device (Plan 18).
  if let fill = input.foregroundFill, let p = input.playing, let doc = input.documents[p.documentID],
     !d.thermalSerious, !d.lowPowerMode, !d.storeFull {
      let start = p.playhead.utteranceIndex
      let toChapterEnd = doc.seconds[max(0, start)..<doc.chapterEnd(containing: start)].reduce(0, +)
      walk(doc, from: start, budget: min(max(toChapterEnd, fill.lowerBound), fill.upperBound), tier: .chapterAhead)
  }
  ```
  (`d` is declared at :131; hoist it above tier 2b.) `seen` keeps the window's jobs out of the fill.
- Tests, `RenderPolicyTests` (helper `snap` gains `chapterStarts:`): (a) nil → the existing suite is the regression; (b) with a 60 s window and a 300…1000 s fill on a chapter ending at index 40, jobs are `[playAhead 5…10] + [chapterAhead 11…39]`, in that order; (c) a chapter with 20 s left is topped up to the minimum into the next chapter; (d) a 3000 s chapter is cut at the maximum; (e) rendered utterances count toward the bound but are not jobs; (f) each of `thermalSerious`, `lowPowerMode`, `storeFull` removes the chapter jobs and leaves the window's; (g) on a charger with `lastPlayed` set, chapter jobs precede prepare jobs and no index repeats; (h) no `playing` → no fill.

### Step 4 — The coordinator decides when
- `Sources/T2SAudio/PlaybackCoordinator.swift`:
  - `CoordinatorConfiguration.foregroundFill: ClosedRange<TimeInterval>? = nil` (:9-23).
  - `public var isForeground = false { didSet { replan() } }` beside `device` (:54).
  - In `replan()` (:429): `input.foregroundFill = isForeground && isListening ? configuration.foregroundFill : nil`, with `private var isListening: Bool { state == .playing || state == .catchingUp }`.
  - `replan()` after `state = .playing` in `play()` (:230) and after `state = .paused` in `pause()` (:236).
  - An `os` `Logger(subsystem: "com.t2s.reader", category: "render.fill")` notice when the passed range flips between nil and a value (`AudioPlayer.swift` already imports `os` in this target) — the phone test reads it in Console.app over USB (the `devicectl` console does not carry os_log; crashreport.md line 208).
- Tests, `Tests/T2SAudioTests/PlaybackCoordinatorTests.swift`, a two-chapter fixture of one-sentence utterances (the builder at :538-539, the forty-sentence pattern at :178-190), `foregroundFill: 5...10` and `windowSeconds: 1`: (a) `isForeground = true`, `play()`, `waitForRenderIdle()` → every utterance of chapter A is actual, chapter B untouched beyond the minimum; (b) in front but paused → only the window's utterance; (c) `isForeground = false`, playing → only the window; (d) `engine.hold()`, play in front, then `isForeground = false`, `release()` → `engine.requests` count is the window's plus one (the job in flight); (e) `seek(toChapter: 1)` in front while playing refills from B's start; (f) `pause()` mid-fill drops the rest (hold/release as in d).

### Step 5 — App wiring
- `App/T2SReader/System/KokoroComposition.swift`: `let foregroundFillSeconds: ClosedRange<TimeInterval>?` beside `playAheadWindowSeconds` (:196) with the doc comment carrying the arithmetic of §2.1; `static let foregroundFillKey = "render.foregroundFillMaxSeconds"` beside `computeUnitsKey` (:205) — a `Double` in `UserDefaults`, `0` disables, `v > 0` gives `min(defaultMin, v)...v`; the value at :355 becomes `computeUnits == .cpu ? 600...1800 : 1200...3600` (before the override); `nil` at :377.
- `App/T2SReader/AppEnvironment.swift:154-155`: `configuration.foregroundFill = kokoro.foregroundFillSeconds`.
- `App/T2SReader/Root/RootPager.swift:208-210`: `env.coordinator.isForeground = phase == .active` on the line after the gate.
- Optional, same commit: under `#if KOKORO_ENGINE`, an `.onChange` on a new `coordinator.isFilling` (read-only, set in `replan`) that calls `KokoroCoreMLEngine.timing("render-ahead fill on/off")`, so the phone's `kokoro-timing.log` shows the fill's edges beside the utterance lines.
- Verification: `scripts/build-app.sh`; then the phone protocol in §4.1.

### Step 6 — Docs
- `docs/HANDOFF.md`: a "Resume here (2026-09-11, render-ahead)" entry; strike the "Owed" line.
- `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` §3.4.1: a row "2b Foreground fill — the rest of the current chapter, clamped 10–30 min (CPU) / 20–60 min (GPU), while frontmost and listening, not hot/low-power/full — after prime, before prepare", and a revision note.
- `crashreport.md` Finding 2b: a pointer to this plan.

### Step 7 (optional) — Bound the metadata loss
`PlayerModel` persists the changed chapters every 30 s while a fill runs, mirroring `PrepareRunner.chapterWriteInterval`: `init(coordinator:library:timeSource: any TimeSource = SystemTimeSource())`, a `persistIfDue()` called from `tick()` (`PlayerModel.swift:319-321`) when `coordinator` has changed chapters and the interval has passed. Test in `Tests/T2SAppTests/PlayerModelTests.swift` with a `ManualTimeSource`: two renders, advance 31 s, tick → the stored chapter carries the refs. Value: the Storage page's `renderedCount` and a jetsam-in-front stop lagging a fill by up to ten minutes.

### Step 8 (optional, after the phone) — `.fair`
`DeviceState.thermalFair` (defaulted init parameter, `DeviceStateMapping` sets it from `DeviceSignals.thermal == .fair`); the policy halves `fill.upperBound` under it. Table tests in `DeviceStateMappingTests` and `RenderPolicyTests`.

### 4.1 The phone protocol (owner)
1. Install the Phone-scheme build; open a novel with 15–25-minute chapters.
2. Play in front for three minutes; `kokoro-timing.log` shows `kokoro utterance` lines at ~1/s (RTF 0.17 × ~6 s utterances) and the scrubber's frontier well past the playhead.
3. Lock ten minutes at 1x, then ten at 1.5x; expect no gap. The log should show no renders during the lock (the window is inside the fill), or a few near its end.
4. Console.app, subsystem `com.t2s.reader`: the `render.fill` notices at play/lock/unlock; `render.pacing` at most once, right after the lock.
5. Note the thermal state after a full fill (Settings shows nothing; the `.serious` guard would show as the fill stopping early in the log).

---

## 5. Open questions for the owner

1. Fill only while listening (this plan), or whenever a document is loaded in front (the window's rule today at `PlaybackCoordinator.swift:426`)? One condition either way.
2. The CPU-path bound, 10–30 min: the A13 pays 5–17 min of full CPU per fill. Keep, or start at 10–20 and raise after the phone test?
3. Low Power Mode: no fill (this plan), or a halved bound?

---
