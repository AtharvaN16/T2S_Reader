# The GPU path, locked: a review of the render flow on an A19 phone

_2026-09-11. A desk review of `dev` @ 869fe6b plus the logging lines committed with this file (the
engine's line numbers below are as of that commit; nothing else moved). Nothing here was run on a
phone — this Mac has none and its owner's 11 Pro is gated off the GPU path by
`KokoroComputeUnits.permitted` — so every claim is from the source, and section 6 says what Harsh's
run on the iPhone 17 Pro should show if the reading is right. Written for that run and for whoever
fixes what it finds. The companion is the `MLComputePlan` probe,
`Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroComputePlanProbe.swift`, for the other open
question on that phone (why its CPU plan compiler never finishes the 15 s generator)._

## 1. What is wired on an A19 phone

| piece | where | what it does on `iPhone18,*` |
|---|---|---|
| chip policy | `KokoroCoreMLModels.swift:60-65`, `:78-83` | `.cpuAndGPU` for `iPhone18,*` with ≥ 5 GB; the `kokoro.computeUnits` default overrides for a session, held to the same floor |
| the two sets | `KokoroComposition.swift:234-253` | main set on the policy's units; `backgroundComputeUnits = .cpu` whenever the main set is not `.cpu` (`:249`); the engine gets `admission: { gate.waitUntilForeground() }` and `placement: { gate.isForeground ? .foreground : .background }` (`:252-253`) |
| the gate | `ForegroundGate.swift:30-39`, `:43-61`; set from `RootPager.swift:211-212` | open only while `scenePhase == .active`; `.inactive` (a lock's first step, Control Center, a banner, the app switcher) closes it too |
| the engine's wrapper | `GatedKokoroCoreMLEngine.swift:92-108` | the admission and placement closures are installed (`:104-105`) before `constructed` is set (`:106`), so no render can reach an engine that lacks them |
| the background set | `KokoroCoreMLResources.swift:31-37` | the 3 s bucket and the t128 duration model: four CPU plans (`kokoro_duration_t128`, `f0ntrain_t120`, `decoder_pre_3s`, `decoder_har_post_3s`) |
| play-ahead | `KokoroComposition.swift:355` → `AppEnvironment.swift:154-155` → `PlaybackCoordinator.swift:429` → `RenderPolicy.swift:121-124` | 600 s × playback rate, in every state — the coordinator does not know front from back |
| the budget | `AppEnvironment.swift:140-141`; `CPUBudget.swift:79-97`; `RenderScheduler.swift:165-169` | while the gate is closed, a render waits until the process's CPU in the trailing 60 s plus the last render's cost fits 36 s |
| screen awake | `RootPager.swift:223-225` | `isIdleTimerDisabled` while warming or while `isBuildingBackgroundSet` — auto-lock is held off; a manual lock is not |

## 2. The flow, step by step

### 2.1 Launch and warm-up (in front)

1. `KokoroComposition.warmUp` (`:457-506`) calls `preload()`; the engine's `load()`
   (`KokoroCoreMLEngine.swift:348-403`) builds the ready set — eight stages, up to `loadWindow` = 4
   plans at once (`KokoroCoreMLModels.swift:213`), each admitted through the gate before it starts
   (`:188`) and then uncancellable inside `MLModel.load` (`:195`). On the 17 Pro from a cold cache
   that was 159 s (HANDOFF, "The phone answered").
2. At readiness `load()` kicks off three things in order (`:389-391`): the 7 s and 10 s buckets
   (`loadLaterBuckets`, `:431-451`), the predictor warm-up (`startPredictorWarmUp`, `:477-489`; GPU
   policies only), and the background set (`startBackgroundSetLoad`, `:512-544`).
3. The background set's task (utility priority) first awaits the predictor warm-up (`:519`) — note
   `awaitPredictorWarmUp` (`:619-622`) only waits for the later-bucket warm-ups that exist at that
   moment, so the t128 CPU plan build usually overlaps the 7 s and 10 s GPU loads and their warm-ups.
   Then it loads its four stages **one at a time** (`window: 1`, `:522`), each admitted through the
   gate *and* held while the phone is thermally serious (`:523-526`, `waitWhileThermallySerious`
   `:559-572`). On the 17 Pro the t128 plan took 134 s alone; the other three came from the cache in
   under a second (HANDOFF, "The background CPU set, measured"). `installBackgroundSet` (`:546-554`)
   then sets `backgroundLoaded`.
4. The app marks the install "warmed" only once `awaitBackgroundSet()` says the set exists
   (`KokoroComposition.swift:483-488`); the status turns `.available` before that (`:479`), so
   playback can start while the set is still building — by design, with the 600 s window as the
   cushion (spec 2026-09-10, decision 12).

### 2.2 Play, in front

Each utterance the policy plans reaches `RenderScheduler.renderWhileHoldingLease`
(`RenderScheduler.swift:157-208`): the budget is asked (`:167-169`; it returns at once in front),
then `engine.synthesize` or the streamed head (`:174-176`). In the engine every piece goes through
`placedPieces` (`:604-616`), which asks `renderSet` (`:579-600`) where to render; in front that is the
main set, on the GPU, and the timing line `kokoro call: … ; set main` (`:930`) records it. The window
fills in ten seconds of GPU (27 calls, RTF 0.04-0.06 measured 2026-09-10).

### 2.3 The lock

The scene goes `.active → .inactive → .background` over about a second. The gate closes at
`.inactive` (`RootPager.swift:212`); `placement()` answers `.background` from then on; iOS refuses
GPU work once the app is actually in the background (E5RT "Insufficient Permission (to submit GPU
work from background)", HANDOFF 16:38). What happens depends on where the engine is:

**(a) A piece is mid-render on the GPU.** The call fails inside `executeKokoroSynthesis`; `render`
logs `kokoro call failed: …` (`:925`) and throws `stageFailed`; `placedPieces` catches it **only if**
the set was the main one *and* `renderPlacement?()` says `.background` at catch time (`:610`), logs
`kokoro call refused in the background; rendering again where it is allowed` (`:611`), asks
`renderSet` again (`:612`) and renders the piece once more (`:614`) — through the background set if
it exists, else after waiting on the gate for the unlock. A second refusal is not retried: it
propagates, the scheduler stores 200 ms of failure silence (`RenderScheduler.swift:181-184`) and the
Reader shows the banner. A streamed head that already emitted pieces keeps them and yields `.failed`
(`RenderScheduler.swift:213-236`).

**(b) The next piece, with the background set loaded.** `renderSet` returns `backgroundLoaded`
(`:583-588`); the piece was cut for the t256 model and the 15 s bucket (`maxPieceTokenCount` = 176,
`:44`), so `renderWithSplitting` first throws `tooManyTokens` for anything over 126 ids (`:972`)
and halves it, then each half renders in the 3 s bucket and, when its predicted audio overflows
the bucket, throws `audioTruncated` (`:936-943`) **after the whole call has run** and is halved
again. So a 15 s piece costs at least two discarded 3 s-bucket renders (one per 88-id half) before
the four-plus that are kept, and every kept call is a full pipeline run — five or more calls
where the GPU path made one, a third or more of them thrown away, all on the CPU under the budget.
The audio is right (more seams, no silence: `KokoroCoreMLResources.swift:35`); the CPU cost per
audio second in the background is what this makes unmeasured, and section 5 item 2 is the fix.

**(c) The next piece, with no background set yet.** `renderSet` loops on the gate (`:589-594`):
the piece parks until the unlock, holding the scheduler inside `synthesize` and the scheduler
holding the arbiter lease (`RenderScheduler.swift:165-166`). Nothing renders while locked; the
600 s of audio already rendered is the whole cushion. This is the designed behaviour (decision 12),
and it is now visible in the log (`kokoro piece placed in the background before the background set
exists; waiting for the foreground`, `:592`, and the matching line when it ends, `:585` or `:597`).

**(d) The budget.** With the gate closed, `waitForHeadroom` (`CPUBudget.swift:79-97`) charges the
process's CPU in the trailing 60 s — which includes a background-set plan build still running from
before the lock (one core, up to 134 s) — against 36 s, and sleeps in ≤ 5 s slices until it fits.
Its "render paced in the background" notice (`:88`) is `os_log` only; nothing of it reaches
`kokoro-timing.log`. The estimate it is given is the *last* render's CPU seconds
(`RenderScheduler.swift:168`, `:179`), which after a GPU stretch is a GPU render's — small — so
the first background-set render is admitted at once and its real cost only counts from the next.

**(e) A background-set stage load in flight.** The gate holds the *next* stage's load, not the
one running: a lock during the t128 build leaves 100 % of a core running in a non-frontmost
process for up to two minutes, the `cpu_resource_fatal` shape from 2026-09-09 15:14 (crashreport.md,
Finding 2, on the A13's main set). `isIdleTimerDisabled` covers the auto-lock; a hand lock during
those two minutes is the exposure. If the stage in flight was the set's last, the set lands
mid-lock — but the parked piece in (c) is waiting on the *gate*, not on the set, and does not use
it until the unlock.

### 2.4 Unlock

The gate opens; every waiter resumes (`ForegroundGate.swift:30-39`); a parked piece re-reads the
placement, gets `.foreground`, renders on the main set (`:597`, `:599`); the budget stops applying;
the scheduler's loop continues with whatever plan the coordinator last set. The later-bucket and
predictor warm-ups that were held on `admission` (`:465-469`, `:484-486`) also resume and
interleave with renders one step per actor turn.

## 3. Races and gaps

Ordered by how likely they are in Harsh's run, with what would show them.

| # | what | where | likelihood on the 17 Pro | what the log would show |
|---|---|---|---|---|
| R1 | **A lock before the background set exists parks every render on the gate; the window is the only cushion.** Designed, but the set's first build is ~134 s of CPU after readiness and the set is *rebuilt from scratch on every app update* (the plan cache is per install, HANDOFF). | `:589-594`; `KokoroComposition.swift:483-488` | high on a first launch after an update, rare after | `kokoro piece placed in the background before the background set exists…` then silence until `kokoro scene active`; audio runs out after 10 min locked |
| R2 | **The background set renders a 15 s piece as five-plus 3 s-bucket calls, a third of them discarded.** Full pipeline runs thrown away on `audioTruncated`; CPU per audio second in the background unknown, and the budget (36 s per 60 s) may not sustain 1× once the buffer drains. | `:972`, `:936-943`, `renderWithSplitting :966-988` | certain whenever a locked phone renders through the set | many `kokoro call: bucket 3 s … set background` lines per utterance, some followed by `kokoro call failed: … audioTruncated`; then `render paced` gaps (not logged today) |
| R3 | **A piece refused mid-lock is retried only if the placement still says `.background` at catch time**, and only once. A lock-and-unlock inside one call, or a second refusal, becomes 200 ms of silence and a banner. | `:610-614` | low (a call is 0.3-0.5 s) | `kokoro call failed: … Insufficient Permission` with no `refused in the background` line after it |
| R4 | **`.inactive` counts as background.** Control Center, a notification banner, the app switcher, an incoming call: the placement flips to `.background` while the GPU is still allowed; a streamed head then parks on the gate (no set) or renders in 3 s pieces on the CPU (set present). | `RootPager.swift:212`; `KokoroComposition.swift:253` | medium — every Control Center pull during play | `kokoro scene inactive` followed by `kokoro piece placed…` lines with no lock |
| R5 | **A cancelled task inside `renderSet` spins.** `waitUntilForeground` returns at once when the task is cancelled (`ForegroundGate.swift:47-52`); the loop has no cancellation check, so a cancelled render parked on the gate loops at full speed until the unlock. Reachable only from a task that is actually cancelled with a render inside — `VoicePreviewModel.swift:54`, a stream consumer that stops early (`GatedKokoroCoreMLEngine.swift:85`, `RoutedEngine.swift:64`); `PrepareRunner.cancel()` only flips the scheduler's flag (`PrepareRunner.swift:116-119`) and `RenderScheduler.cancel()` never cancels the task in flight (`RenderScheduler.swift:120-123`). | `:582-595` | low today; one line to close | a `cpu_resource_fatal` while locked with no `kokoro call` lines near it |
| R6 | **A failed background-set load is final for the session.** `startBackgroundSetLoad` runs once (`:513` guards on `backgroundLoadTask == nil`), a failure is logged and the set stays absent (`:541`); every later background piece parks on the gate, and the install is never marked warmed, so Prepare skips too. | `:512-544` | low (a transient `MLModel.load` failure) | `kokoro background set failed to load: …` once, then R1's lines on every lock for the rest of the session |
| R7 | **A lock during a background-set plan build.** The build cannot be cancelled and runs at 100 % of a core in a non-frontmost process. | `:521-535`; `KokoroCoreMLModels.swift:188-195` | low with the screen kept awake; a hand lock in the ~2 min after readiness on a fresh install | a `cpu_resource_fatal` report with `MLModel.load` → `E5RT::E5CompilerImpl::Compile` on the heaviest stack, in the two minutes after `kokoro background stage kokoro_duration_t128 loaded…` is *missing* |
| R8 | **The parked render holds the arbiter lease and survives a stop.** A stop while locked leaves the stale utterance parked; on unlock it renders first (one wasted GPU call), and Prepare could not take the lease meanwhile. | `RenderScheduler.swift:165-169`, `:74-76` | low impact | a `kokoro utterance` line for an utterance the reader had stopped |

Not a race but worth knowing: `awaitPredictorWarmUp` (`:619-622`) sees only the later-bucket
warm-ups that exist when it is called, so the background set's t128 CPU build normally overlaps
the 7 s and 10 s GPU loads and the live renders — longer "hot phone", not a fault.

## 4. What the timing log says, and what it cannot

`Library/Caches/kokoro-timing.log` (`KokoroTimingLog`), every launch under a `==== launch …` header,
wall-clock stamps. Everything below is a `KokoroCoreMLEngine.timing(...)` line.

**There today (before this commit):**

| line | where | tells you |
|---|---|---|
| `kokoro stage <name> loaded in N s (i/14)` + `kokoro main set loaded: …` | `:341-342` | each main-set plan: cached (< 1 s) or built (tens of seconds) |
| `kokoro g2p built in N s` | `:388` | |
| `kokoro bucket 7 s ready; buckets 3,7,15` | `:463` | the later buckets landing |
| `kokoro predictors warmed: … in N s` / `predictor warm-up failed` | `:502`, `:498` | the GPU first-prediction cost |
| `kokoro background stage <name> loaded in N s (i/4) on coreml-cpu` + summary | `:532-533` | the set's plan builds |
| `kokoro background set ready: buckets 3, duration t128` / `failed to load` | `:553`, `:541` | whether a locked phone can render at all |
| `kokoro call: bucket N s, audio, wall, RTF; stage split` | `:930` | every pipeline call |
| `kokoro call failed: …` | `:925` | the refusal text, truncation, anything Core ML threw |
| `kokoro call refused in the background; rendering again where it is allowed` | `:611` | the mid-lock retry |
| `kokoro utterance (whole/streamed): g2p, pieces, audio, total, RTF` | `:709` | one per utterance |
| `kokoro warm-up finished in N s` / failed / route closed; install lines; plan cache wiped | `KokoroComposition.swift:476`, `:497`, `:502`, `:431`, `:440`, `:279`; `KokoroCoreMLInstall.swift:120-311` | the launch's one-time work |

**Missing, and why a failure could not be diagnosed from the file alone:**

1. **When the lock happened.** No line marked the scene or the gate; the reader had to note the
   time by hand and read the stamps against it. *Added:* `kokoro scene active|inactive|background;
   foreground gate open|closed` (`RootPager.swift:216`).
2. **Why a render is silent.** A gap in the call lines could be the gate (no set), the budget, a
   thermal hold, or a failed load, and the file could not tell them apart. *Added:* the `renderSet`
   wait lines (`:585`, `:592`, `:597`) and the thermal hold lines (`:565`, `:570`). *Still missing:*
   the budget's decisions — `CPUBudget`'s notice (`CPUBudget.swift:88`) and the per-render CPU
   seconds the scheduler measures but never prints (`RenderScheduler.swift:179`) live in `T2SCore`,
   which cannot see the timing log; section 5 item 1.
3. **Which set a call rendered on.** `kokoro call:` did not say. *Added:* `; set main|background`
   on that line (`:930`), from `lastRenderSet` (`:607`, `:613`).
4. **A later bucket's failure** went to `os_log` at error level only (`timingLog.error`), never to
   the file. *Changed* to a `timing` line (`:447`).
5. **How far ahead the buffer was at the lock** — the coordinator's business, not the engine's; the
   file cannot say whether 10 min were in hand or 30 s. Section 5 item 1 (the scene line is the
   natural place to add the playhead and the rendered horizon).
6. **Memory.** No footprint line; the GPU path's peak is unmeasured on the 17 Pro (12 GB, so not
   the risk it is on the 11 Pro).

## 5. Improvements, ordered by value

Each is small, has a file:line, and a test that would pin it. None is implemented here; the
logging lines above are the only code change with this review.

1. **Make the pacing visible in the timing file.** Give `CPUBudget` an optional
   `report: (@Sendable (String) -> Void)?` (`CPUBudget.swift:32-43`) called with the same text as the
   `render.pacing` notice (`:88`), and have `RenderScheduler` report `lastRenderCPUSeconds` and the
   seconds waited after each render (`RenderScheduler.swift:179-180`); wire both to
   `KokoroCoreMLEngine.timing` in `AppEnvironment.live()` (`:141`). Add the playhead and the rendered
   horizon to the scene line in `RootPager` (`:216`; `env.player` has both). *Test:* `CPUBudgetTests`
   and `RenderSchedulerTests.aBackgroundRenderWaitsOnTheBudget` assert the report closure receives
   one line when pacing engages and none in front. *Value:* it is the difference between "the
   audio stopped" and knowing which of four mechanisms stopped it, and it measures the background
   set's CPU cost per audio second — the number that decides whether a 3 s-bucket CPU set can hold
   1× under 36 s per 60 s at all.

2. **Cut for the background set before rendering, not after.** In `placedPieces` (`:604-616`), when
   `renderSet` returns the background set, re-cut the piece with the existing cutter
   (`pieces(ids:owners:words:firstPieceCap:)`, `:1270`) at a cap sized for the 3 s bucket —
   about 36 ids, from `streamingFirstPieceTokenCount` = 48 ≈ 3 s (`:49`) with margin — so no call is
   run to be thrown away and `tooManyTokens`/`audioTruncated` become the rare path they were meant
   to be. *Test:* the model-backed `aBackgroundPlacementRendersThroughTheBackgroundSet`
   (`KokoroCoreMLLoadTests.swift:101-124`) gains an assertion that the utterance trace's piece count
   equals the number of `kokoro call` lines, i.e. no discarded render; a synthetic test on the cut
   itself needs no model. *Value:* halves or better the background CPU per audio second, which
   R2 says is the path's real risk once the buffer drains.

3. **Place by `.background`, not by the gate.** Keep the gate on `.active` for plan builds, but
   give the placement its own flag set from `.background` (`RootPager.swift:226-238` already switches
   on it) — a Control Center pull or a banner must not park a streamed head or push it into 3 s
   pieces. A GPU call that starts in `.inactive` and is refused a moment later is already covered by
   the retry (`:610-614`). *Test:* a `KokoroComposition`-level test of the placement closure with the
   gate closed and the flag clear expects `.foreground`. *Value:* removes R4, the one race a
   listener will hit every session without locking.

4. **Close R5 and R6 in the engine.** In `renderSet` (`:582-595`) throw `CancellationError` when
   `Task.isCancelled` after `admission()` returns (make it `throws`; `placedPieces` already is). In
   `startBackgroundSetLoad`'s failure path (`:540-542`) clear `backgroundLoadTask` and re-kick the
   load from `renderSet` (or `awaitBackgroundSet`) the next time the gate is open. *Test:* for R5, a
   cancelled `synthesize` task with `placement { .background }`, no set and a closed gate must throw
   within milliseconds (assert with `ContinuousClock`); for R6 a stage-loader seam is needed —
   `loadStages` taking an injectable loader is the smallest. *Value:* one spin closes a
   `cpu_resource_fatal` shape; the retry turns a one-off load failure into a delay instead of a
   session without background audio.

5. **Make the refusal retry a decision, not a coincidence.** Extract "should this `stageFailed` be
   rendered again, and where" into a static function of (error text, set used, placement at start,
   placement now) — retry when the text names the background-GPU refusal regardless of the
   placement at catch time, and allow a second try through the background set — and call it from
   `placedPieces` (`:610`). *Test:* pure-function cases, like `renderSplittingOnOverflow`'s
   (`KokoroCoreMLLoadTests.swift:80-97`). *Value:* R3, cheap insurance on the exact path Harsh will
   exercise by locking mid-sentence.

6. **Say "keep the phone unlocked" while the background set builds.** No code can cancel
   `MLModel.load`; `isIdleTimerDisabled` already covers the auto-lock (`RootPager.swift:223-225`);
   what is left of R7 is a hand lock in the ~2 min after readiness on a fresh install, and the veil
   already knows the state (`KokoroStatusModel.isBuildingBackgroundSet`,
   `KokoroComposition.swift:91-93`). One line of copy on the veil while it is true. *Test:* a view
   snapshot is not in this repo's habits; the model's flag is already covered. *Value:* small, but
   it is the only mitigation for the one crash shape still open on the GPU path.

## 6. What Harsh's run should show (a reading guide)

Pull the file afterwards with `xcrun devicectl device copy from --domain-type appDataContainer
--device <UUID> com.antarlabs.t2sreader Library/Caches/kokoro-timing.log`. Under the last
`==== launch` header:

**Play, then lock with the set ready** (the second launch of the same install, or a first launch
left in front for ~2½ min after "ready"):

```
kokoro scene active; foreground gate open
kokoro background set ready: buckets 3, duration t128        ← must precede the lock
kokoro call: bucket 15 s, … ; set main                        ← the window filling on the GPU
kokoro scene inactive; foreground gate closed
kokoro scene background; foreground gate closed
kokoro call: bucket 3 s, … ; set background                   ← several per utterance (R2)
kokoro call failed: … audioTruncated …                        ← a discarded 3 s render (R2), then more 3 s calls
kokoro utterance (whole): … pieces 5, …
```
Gaps of a minute between `set background` calls with no line in them are the budget (item 1 is
what would name them). The RTF on the `set background` lines is the number nobody has: if the
kept calls' wall time per audio second, times the discard ratio, is above ~0.6, the 3 s set cannot
hold 1× under the budget and the buffer will drain at that rate.

**Lock during the ~2 min after "ready" on a fresh install** (the set not built):

```
kokoro warm-up finished in N s
kokoro predictors warmed: …
kokoro background stage kokoro_duration_t128 loaded in 134 s   ← may still be running at the lock (R7)
kokoro scene background; foreground gate closed
kokoro piece placed in the background before the background set exists; waiting for the foreground
   … nothing until …
kokoro scene active; foreground gate open
kokoro piece placed in the main set after waiting N s for the foreground
```
Audio must last the whole lock from the 600 s window. If it does not, the window was not full at
the lock (a lock right after Play on an unrendered chapter fills in ~10 s; a seek into unrendered
text starts empty).

**A lock mid-call** (lock while a sentence is being rendered — hard to time; a long chapter's first
Play then an immediate lock is the best chance):

```
kokoro call failed: … Insufficient Permission (to submit GPU work from background) …
kokoro call refused in the background; rendering again where it is allowed: …
kokoro call: bucket 3 s, … ; set background     (or the "waiting for the foreground" line)
```
A `call failed` with no `refused` line after it is R3.

**What would be a failure to report back with the file:** a `cpu_resource_fatal` in the phone's
crash store dated inside a lock (R5 or R7 — the stack tells which: `E5CompilerImpl::Compile` is
R7); the Reader's "stageFailed" banner (R3, or a second refusal); silence with the buffer full
(R1 on a launch whose `background set ready` line is missing, or R6 with a `failed to load` line).
