# Crash report — Harsh's `phone-warmup-download-cloud` on the owner's iPhone 11 Pro

_2026-09-10, evening. Branch tip `ae23248`, tested on the owner's iPhone 11 Pro (A13, 4 GB,
iOS 26.6.1, CoreDevice `A48A2E54-C7DE-5BCD-A073-60A97B3DB384`) from a Mac with Xcode 26.3.
Every claim below was checked against the source by an adversarial pass (three skeptics, one per
finding, then a completeness critic); where they corrected the first draft, the correction is in.
The `.ips` files cited are kept in `crashreport-ips/`._

## Summary

1. **The model download aborts on the first non-2xx response and never retries.** Four fresh
   launches out of four failed within seconds. The status code is discarded before it can be
   logged; Hugging Face 429 throttling is the likely cause (13 × 429 reproduced from the Mac with
   a HEAD sweep of the same 72 URLs — not observed on the phone itself). **On `dev` too.**
2. **Locked during warm-up (CPU path): survived.** A non-fatal `cpu_resource` warning shows the
   in-flight plan builds held 100 % CPU through the lock; a lock longer than 60 s there is the
   one `cpu_resource_fatal` shape the branch does not cover on the A13.
3. **Locked four minutes during playback (CPU path): no crash, no kill, audio starves for a
   second or two once a minute.** The `CPUBudget` bursts ~70 s of audio, then sleeps ~60 s; the
   play-ahead is 60 s. Two small fixes are named below.
4. **The GPU path (`cpuAndGPU`, the 17 Pro's default) aborts on the 11 Pro** during plan
   compilation — `std::bad_alloc` in MPSGraph, `SIGABRT` — before any lock. The chip policy is
   right to keep the A13 on the CPU; the session override can still put it there.
5. **The owner's "working" `t2s` crashed eight times today.** Three different binaries. The
   current one (built 19:40, post-PR #16) dies only the MLX-on-Metal way — the one fix that is
   **branch-only**; the two other fixes are already on `dev`.

## How it was tested (so nothing working was touched)

- `dev` (`68c8b5a`) and the working `t2s` app were not modified.
- His branch is checked out in `.worktrees/phone-warmup-download-cloud` and built under a
  **second identity** — `T2S_BUNDLE_ID = com.t2s.reader.harsh`, app group
  `group.com.t2s.reader.harsh`, display name **t2s H** — so it installs beside `t2s`. Two copies
  must never share an app group.
- The owner's team is a **free personal team**: three app slots per device, an app with an
  extension counts twice. `t2s` + its share extension used two, so the test copy is built
  **without the share extension** (a worktree-only edit to `App/project.yml`, never to be
  committed) and the Spike Harness was uninstalled from the phone, with the owner's OK.
- Signed Release build from the CLI (`CODE_SIGN_STYLE=Automatic ENABLE_DEBUG_DYLIB=NO
  -allowProvisioningUpdates`), installed and launched with `devicectl`, console attached
  (`-kokoro.timingConsole YES`). The phone was on USB the whole time (see "conditions not
  recorded" under Finding 2b).
- One diagnostic line was added in the worktree only, in `KokoroCoreMLInstall.swift`'s download
  `catch` (line 143), mirroring the underlying `URLError` into the timing stream; the real error
  goes to `os_log`, which the `devicectl` console does not carry. Uncommitted; not on the branch.
- The model was pushed to the phone over USB after the download proved impossible (workaround
  under Finding 1).

## Finding 1 — the download aborts on the first non-2xx response, and never retries

> **Fixed on `dev` in `5d40ac8`** (2026-09-10 late): `HTTPStatusError(status:retryAfter:)`, an attempt loop with
> `Retry-After` or 2/4/8/16 s backoff up to five attempts for 429/408/5xx and dropped connections, a 404 failing at
> once, `Failure.download(path, status:)`, and a `.retrying` progress the veil shows over a held bar. Not done:
> `Range` resume, one session per install, a background `URLSessionDownloadTask`.

**Applies to `dev` as well.** `KokoroCoreMLInstall.swift` and `KokoroCoreMLManifest.swift` are
byte-identical between `dev` (`68c8b5a`) and this branch tip (`git diff dev HEAD -- <paths>` is
empty; no commit in `dev..HEAD` touches them). The working `t2s` is unaffected only because its
model is already on the phone; the next fresh install from `dev` hits this.

**Observed.** Four fresh launches (the last two after a full reinstall), each failing a few
seconds in, each on a different file — the installer resumes per file, so every launch got a
little further:

```
21:57:38.644 kokoro install failed: download("coreml/kokoro_decoder_har_post_10s.mlpackage/Manifest.json")
22:00:27.956 kokoro install failed: download("coreml/kokoro_decoder_pre_15s.mlpackage/Manifest.json")
22:02:10.415 kokoro download failed for coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel: Error Domain=NSURLErrorDomain Code=-1011 "(null)"
22:11:06.384 kokoro download failed for coreml/kokoro_decoder_har_post_15s.mlpackage/Manifest.json: Error Domain=NSURLErrorDomain Code=-1011 "(null)"
```

**Mechanism.** `wifiDownloader` (`KokoroCoreMLInstall.swift:256-258`) throws a bare
`URLError(.badServerResponse)` (-1011) for any response outside 200–299 — the status code never
leaves that closure. The per-file `catch` (`:140-144`) deletes the `.part`, logs
`String(describing: error)` and throws `Failure.download(path)`, which carries only the path.
There is no attempt loop around the `downloader(...)` call (`:131-136`), no backoff, nowhere;
the only retry in the area is the post-install warm-up's `for attempt in 1...2`
(`KokoroComposition.swift:406`). The failure propagates out of `install(progress:)` (`:89`), so
`compileMissingStages` never runs; `KokoroComposition.swift:377-381` catches it and shows
"The Kokoro voice could not be downloaded. It will try again the next time the app opens."
(`:453`). Each file also opens its own ephemeral `URLSession` (`:246-253`): 72 TLS handshakes
and 72 redirect chains through huggingface.co to its CDN per install.

**Likely cause: Hugging Face throttling the burst.** From the Mac, a HEAD sweep of the
manifest's 72 URLs in quick succession returned **13 × HTTP 429**; the same URLs a few seconds
apart are 200 every time. The phone's four -1011s are consistent with 429 — and also with a
5xx or a failed CDN redirect; the phone never surfaced a status, and if the Mac shares the
Wi-Fi's public address its sweep may itself have been throttled by the phone's earlier attempts.
(An earlier reading of that sweep — 404s on 17 voices — was a mistake in the sweep: those voices
are pinned under `repositoryPath: "kokoro.js/voices/…"` and resolve fine. Recorded so nobody
chases it.)

**Consequences.** A fresh install fails on the first bad response and the route stays closed
until a relaunch, which must reach the foreground before the download even starts
(`KokoroComposition.swift:256-260`). Progress is kept per file, so repeated relaunches do get
there eventually; how many is not measured.

**What would fix it** (the critic's concrete version):
- In `wifiDownloader` (`:256-258`) throw a typed error carrying `http.statusCode` and the parsed
  `Retry-After` — the pattern already exists at `HTTPVoiceEngine.swift:226-229` with
  `HTTPVoiceError.rateLimited(retryAfter:)` (`:95`).
- Wrap the `downloader(...)` call (`:131-136`) in an attempt loop: ~5 attempts, backoff
  2/4/8/16/32 s capped at 60 s, `Retry-After` overriding; retry 429, 408, 5xx and `URLError`
  `.timedOut` / `.networkConnectionLost` / `.cannotConnectToHost`; never other 4xx (a mis-pinned
  path must fail fast). Keep the `CancellationError` passthrough (`:137-139`). Add a
  `Progress.retrying` case so the veil does not look stalled, and a 429-then-200 test through the
  downloader seam (`KokoroCoreMLInstallTests.swift:98`).
- The `.part` is deleted on every failure (`:126`, `:141`) and there is no `Range` header
  (`:255`), so a retry restarts the file from byte 0 — fine for a 617-byte `Manifest.json`,
  costly for the 15 s generator's `weight.bin`; a `Range: bytes=<part size>-` resume on retry
  when the server answers 206 is worth it.
- One `URLSession` per install instead of one per file.
- `Failure.download(String)` is a public `Hashable` case; giving it a status changes the enum
  and the tests that match `.download(path)`.
- Downloads are not gated on the foreground (only compiles await admission, `:200`), and the
  session is in-process (`session.bytes(from:)`), so a backoff sleep that spans a suspension
  fails on resume and aborts the install as today. A background `URLSessionDownloadTask` is the
  larger fix; the retry loop should at least treat resume-after-suspend failures as retryable.

**Workaround used for this test.** This Mac's copy of the model (`App/Resources/KokoroCoreML`,
fetched 2026-09-04 at the same revision; verified against the manifest's SHA-256s) was pushed
into the app's container over USB:

```bash
xcrun devicectl device copy to --device <uuid> --domain-type appDataContainer \
  --domain-identifier com.t2s.reader.harsh \
  --source <a folder holding coreml/ voices/ runtime/> \
  --destination "Library/Application Support/KokoroCoreML/2e878c6a/staging"
```

The installer counts a staged file whose size and SHA-256 match as already downloaded
(`:107-117`, `:159-165`), so the next launch went straight to the compile:
`kokoro model installed in 10 s`. Two traps in `devicectl copy to`: it spills a directory's
*contents* into the destination (shape the source like `staging/` itself), and
`--remove-existing-content true` writes as **uid 0**, leaving `2e878c6a/` and `staging/`
root-owned so the app cannot create `compiled/` beside them (`NSCocoaErrorDomain 513`) — the only
way back is uninstall + reinstall. The push without that flag writes as the app's uid.

## Finding 2 — lock during warm-up (CPU path, the 11 Pro's default): survived, with a caveat

Launch 22:12:08 with the model pre-seeded; the owner locked the phone for about 30 s during the
stage loads and unlocked it. From the app's own `Library/Caches/kokoro-timing.log`:

```
22:12:09.479 kokoro stage kokoro_f0ntrain_t600 loaded in 0.52 s (1/14)
22:12:10.667 kokoro stage kokoro_decoder_pre_15s loaded in 0.93 s (4/14)
22:12:57.635 kokoro stage kokoro_duration_t128 loaded in 48.68 s (5/14)
22:13:02.177 kokoro stage kokoro_decoder_har_post_3s loaded in 51.99 s (6/14)
22:17:39.780 kokoro stage kokoro_duration_t256 loaded in 330.82 s (7/14)
22:17:40.593 kokoro stage kokoro_decoder_har_post_15s loaded in 329.92 s (8/14)
22:17:41.031 kokoro warm-up finished in 332.1 s
22:17:44.154 kokoro bucket 10 s ready; buckets 3,7,10,15
```

- The process survived (still running; no crash report). 332 s to ready against the 206 s the
  HANDOFF measured on this phone with the bundled model — the lock may account for part of it.
- The gate (`KokoroCoreMLModels.loadStages(admission:)`, awaited before each build starts, up to
  `loadWindow = min(4, cores)` = 4 builds in flight, `:178`, `:190`) had nothing to hold: all
  eight readiness builds had already started before the lock, and stages 7–8 ran 330 s straight
  through it. `MLModel.load` cannot be cancelled mid-build.
- The phone wrote a non-fatal `cpu_resource` warning for `t2s H` at 22:16:59 (bug type 202,
  "90 seconds cpu time over 90 seconds (100 % cpu average), exceeding limit of 50 % cpu over
  180 seconds", action taken: none): the builds held the CPU at 100 % through the lock.
- **The residual exposure on the A13:** a manual lock longer than 60 s while those builds run is
  exactly "80 %+ of a core over 60 s, not frontmost" — `cpu_resource_fatal`. The gate cannot
  stop a build already running, and `CPUBudget` paces renders only, not plan builds
  (`CPUBudget.swift:6-10`; its only callers are the render scheduler and, through it, Prepare).
  The branch's mitigation is `isIdleTimerDisabled` while warming (`RootPager.swift:215-216`),
  which prevents *auto*-lock. A ~30 s lock does not test this; a > 90 s manual lock during the
  first warm-up would, and is still owed. Short of a smaller `loadWindow` on a first launch, the
  honest fix is the screen staying awake plus a line of copy: don't lock during the first
  warm-up.

## Finding 2b — 4 minutes locked during playback (CPU path): no crash, no kill, audio starves once a minute

> **Partly fixed on `dev` in `abb3875`**: the sample floor — `CPUBudget.record()` after every render, foreground
> included, so the first background wait reflects the real trailing minute. The play-ahead value
> (`KokoroComposition.swift:299`) and the burst-vs-pace question are still Harsh's.
>
> **And on `render-ahead-by-chapter` (2026-09-11)**: the foreground renders the rest of the
> current chapter — 10–20 min on the CPU path, while frontmost and listening — so a locked loop's
> window is already rendered and it only tops up; the budget below can hold a buffer but never grow
> one (~0.9 audio-seconds per wall-second at 1x, from this table).
> `docs/superpowers/plans/2026-09-11-render-ahead-by-chapter.md`; its §4.1 phone protocol is owed.

The owner imported "The Gift of the Magi" (Gutenberg #7256) into `t2s H`, played it, locked the
phone at about 22:20 and unlocked at about 22:24. Their report: *"a couple of times the audio
stopped… the moment the screen was on the audio resumed. It was not a crash but the process might
have been paused. When the audio was playing, it worked well without hiccups."*

The timing log agrees. Renders came in bursts, each followed by a pause of about a minute:

| burst start | calls | audio produced | render wall | pause after | buffer over the cycle |
|---|---|---|---|---|---|
| 22:19:52 | 11 | 68.5 s | 14.3 s | 62 s | ≤ 60 s ahead → out ~2 s before the next burst |
| 22:21:07 | 11 | 70.0 s | 13.5 s | 61 s | out ~1 s before the next burst |
| 22:22:21 | 11 | 69.7 s | 13.2 s | 55 s | just holds |
| 22:23:28 | 7 | 41.9 s | 7.7 s | 41 s | just holds (unlock ≈ 22:24:15) |
| 22:24:15 | 61 | 369.5 s | — | — | in front: steady 9 s cadence, no gaps |

101 calls, 619 s of audio in 104 s of render wall time — **RTF 0.167** on the A13 CPU (7 s
bucket 0.136, 15 s bucket 0.21). No new report in the crash store; the process stayed alive.
Compare the working `t2s`'s 11:58 `cpu_resource_fatal` (though see the comparison section for
what that one actually was).

**Mechanism** (`Sources/T2SCore/Render/CPUBudget.swift`; defaults `windowSeconds = 60`,
`budgetSeconds = 36`, constructed at `AppEnvironment.swift:135`):
- Not frontmost, `RenderScheduler.swift:167-169` calls `waitForHeadroom` before each synthesis;
  it loops while `used + estimate > 36 s` of process CPU in the trailing 60 s, sleeping 1–5 s
  slices; in the foreground it returns at once (`:70-88`).
- The 36 s per burst is **inferred from the pause length, not logged**: the timing lines carry
  wall and RTF only; the scheduler measures `lastRenderCPUSeconds` (`RenderScheduler.swift:171`,
  `:179`) but never prints it, and `CPUBudget`'s "render paced in the background" notice
  (`:79`) is `os_log` (`render.pacing`), which the console does not carry. ~14 s of multi-core
  render wall time costing ~36 s of CPU is the back-calculation.
- The CPU path's play-ahead window is 60 s: `KokoroComposition.swift:299` sets
  `playAheadWindowSeconds` to `nil` for `.cpu` (600 for the GPU path);
  `AppEnvironment.swift:148-149` applies it to `CoordinatorConfiguration.windowSeconds`
  (`PlaybackCoordinator.swift:16`, default 60), which reaches the plan as
  `PolicyInput.windowSeconds` (`:429`; `RenderPolicy.swift:123` multiplies it by the playback
  rate). **It applies in every state, not "while in front"** — the doc comments at
  `KokoroComposition.swift:154-157`, `AppEnvironment.swift:146-147` and `HANDOFF.md:142` that say
  "while in front" are wrong, and the GPU phone's 600 s window also drives its background CPU set
  (`HANDOFF.md:153`).
- Each burst fills the buffer to 60 s ahead; each pause is 55–62 s; so the buffer runs dry a
  second or two before the next burst on most cycles. On unlock the gate opens, the budget stops
  applying, the render resumes at once.
- **A second mechanism the first draft missed:** `CPUBudget` records a sample only inside
  `waitForHeadroom`'s loop (`:73-74`), which never runs in the foreground, and the scheduler's
  own CPU measurement adds none. So the first background call's floor (`:58-62`) is the newest
  sample at or before now − 60 s — possibly the launch sample — and it is charged *all* CPU since
  then (the 332 s warm-up plus every foreground render). The first background render after any
  foreground rendering therefore waits up to a full window regardless of the real trailing
  usage (the doc at `:13-15` admits this). That is a guaranteed first-cycle starve on every lock,
  independent of the window size.

**What would fix it:**
- Fix the sample floor first, independently of the window: have `RenderScheduler` record a
  `CPUBudget` sample after every render, foreground included (after `RenderScheduler.swift:179`,
  e.g. `_ = budget?.usedInWindow()`), so the first background wait reflects the real trailing
  60 s. This alone removes the guaranteed first-cycle starve.
- Then size the CPU path's window at ≥ 2 budget cycles: `KokoroComposition.swift:299`
  `computeUnits == .cpu ? nil : 600` → a CPU value of 150–180 s. Not 600: at RTF 0.167 that
  is 100 s of all-core rendering at every play start on an unrendered document, every seek into
  unrendered text and every rate or voice change (× rate: 150 s at 1.5×), with no thermal or
  low-power gate on tier-1 play-ahead (only tier 3 checks `thermalSerious` / low power,
  `RenderPolicy.swift:132`) — and, since the window is not foreground-only, many more minutes of
  60 %-duty background rendering per lock.
- If smoother background playback is wanted, pace rather than burst: in `waitForHeadroom` admit
  the next render once `lastRenderCPUSeconds / 0.6` wall-seconds have passed since the previous
  one began, keeping the ≤ 5 s slices so a foreground return is noticed. Note the scheduler
  waits while holding the arbiter lease (`RenderScheduler.swift:165-169`) and Prepare shares the
  same code (`PrepareRunner.swift:290`).
- Make the pacing observable: print `lastRenderCPUSeconds` on the render timing line and mirror
  the `render.pacing` notice into the timing stream, then re-run this test and replace "about
  36 s" with a measured number.
- The sustainable rate: ~70 s of audio per ~76 s cycle at 1×. The window and the consumption
  both scale with playback rate (`RenderPolicy.swift:123`), so above ~1.15× the CPU path cannot
  keep up in the background at all.

**Conditions (from the owner):** playback at 1×; the phone was on USB power throughout — `RootPager.swift:312` feeds the coordinator's device state and
charging selects tier 3 (`RenderPolicy.swift:131-140`), which plans the whole document with a
3 h budget and would change the burst shape entirely, though the observed 60 s bursts say the
plan was tier 1; the lock time relative to the 22:19:52 burst is approximate.

## Finding 3 — the GPU path cannot be built on the 11 Pro: the plan compiler runs out of memory and aborts the app

The GPU-path lock test never reached a lock. Launched with `-kokoro.computeUnits cpuAndGPU`
(22:42:38, console attached; a first attempt at 22:28 had been cut short by a relaunch from the
icon, which drops the argument), the loader took six stages from the cache the first attempt
had left, then died compiling the next:

```
22:42:41.806 kokoro stage kokoro_decoder_har_post_15s loaded in 1.40 s (5/14)
22:42:42.557 kokoro stage kokoro_decoder_har_post_3s loaded in 2.16 s (6/14)
MetalPerformanceShadersGraph/MIL/Files/MILToMLIRRewriter.mm:504: failed assertion
  `MIL->MLIR Lowering Failed for op: tensor<fp16, [1024, 640]> var_2402_cast_fp16__weight__0 = const()[val = tensor<fp16, [1024, 640]>(LEGACYBLOBFILE(path = …/e5bundlecache/23G83/2F6E7203…/main_eir/model.espresso.weights))]`
Exception: std::bad_alloc
App terminated due to signal 6.
```

The phone's report — `T2SReaderKokoro-2026-09-10-224635.ips`: bundle `com.t2s.reader.harsh`,
role Foreground, launched 22:42:39, `EXC_CRASH SIGABRT` at 22:46:31 on
`com.apple.root.user-initiated-qos`; frames `abort` ← `__assert_rtn` ← `MTLReportFailure` ←
`MILToMLIRRewriter::rewrite` ← `lowerMILProgram` ← `-[MPSGraphExecutable
initWithMILProgram:executableDescriptor:]` ← `Espresso::MPSGraphEngine::compiler::build_segment`
← `Espresso::net::__build`. The assertion names a plan-cache blob, not the stage; after stages
5–6 the readiness stages still outstanding were the two duration models (`t128` / `t256`), so it
was one of those. A `std::bad_alloc` lowering a 1024×640 fp16 constant (1.3 MB) means the
process was already at its memory ceiling: 4 GB phone, up to four MPSGraph compiles in flight,
each holding its whole MIL program. On the 17 Pro (12 GB) the same compiles took 125–158 s each.
The phone also logged non-fatal `cpu_resource` warnings for this process at 22:30 and 22:44
(94–98 % CPU over ~90 s): the GPU plan compile is a CPU-bound job.

**What this means for the branch.** `KokoroComputeUnits.defaultPolicy(machine:)` is right to
keep the A13 on the CPU — the GPU path is not merely slower here, it is fatal — and right to
leave the A14–A18 phones on the CPU until one is measured. Two things follow:
- The session override `kokoro.computeUnits` (a user default) can put any phone on the GPU path;
  on a 4 GB phone that is a guaranteed abort at first launch, before the veil can say why. Gate
  the override by `ProcessInfo.processInfo.physicalMemory`, or compile GPU stages one at a time
  on phones under ~6 GB — the concurrent compile is what tips it over.
- A memory floor belongs in `defaultPolicy` next to the chip test.

The playback-lock comparison on the GPU path therefore stays a 17 Pro test. The CPU-path result
(Finding 2b) is the 11 Pro's whole story.

## Comparison with the working `t2s`: eight crashes today, three binaries, one class left

The owner's impression is that `t2s` (`com.t2s.reader`) works fine on the 11 Pro. The phone's
crash store has **eight reports for it today**, from **three different binaries** (main-binary
UUID in each `.ips`), all before `t2s H` first launched at 21:57:

| binary | launched | report | what | class |
|---|---|---|---|---|
| `d32acb6f…` (not on this Mac) | 03:25, 04:00, 11:03 | 03:25, 04:00, 11:18 `EXC_BREAKPOINT`, Non UI, dead < 1 s after launch (11:18: 15 min) | `closure #1 in static PrepareTask.register()` → `swift_task_checkIsolated` → `dispatch_assert_queue` on queue `com.apple.BGTaskScheduler (com.t2s.reader.prepare)` | (b) Prepare handler |
| `3920dd54…` (not on this Mac) | 11:57 | 11:58 `cpu_resource_fatal`, Non-Frontmost, **on AC**, sampled from 3 s after launch, one thread in CoreML → Espresso: 48 s CPU over 48 s (99 %), **killed** | a background Prepare launch building a plan from cold — the `BGProcessingTask` shape (`requiresExternalPower`, `PrepareTask.swift:43`) — **not** a foreground warm-up outliving a lock | (a) plan builds in a background launch |
| same | 12:15 | 12:15 `EXC_BREAKPOINT`, Non UI, < 1 s | Prepare handler, as above | (b) |
| `c7863998…` (not on this Mac; **pre-merge**, launched 16:46, PR #16 merged 18:20 EDT) | 16:46, 17:45 | 17:45 (Non UI, 58 min) and 18:00 (**Foreground**, 15 min) `EXC_BREAKPOINT` | Prepare handler, as above | (b) |
| `32128542…` = Xcode DerivedData Release build of **19:40 tonight** (dSYM present) — `dev` after PR #16 | 21:32, 21:39 | 21:39 (Non UI, 7 min) and 21:54 (Non UI, 15 min) `SIGABRT` | C++ exception out of `mlx::core::gpu::check_error(MTL::CommandBuffer*)` in Metal's completion handler → `std::terminate` → `abort()`; app frames `RenderScheduler.renderWhileHoldingLease` → `RoutedEngine.synthesize` → `KokoroCoreMLEngine.prepare` → `EnglishG2P.phonemize` → `BARTModel.generate` → mlx eval, queue `com.t2s.reader.kokoro-coreml` | (c) MLX on Metal in the background |

**Which fixes are where** (verified against `git diff dev HEAD`):
- **(a)** the `ForegroundGate` awaited before each compute-plan build
  (`KokoroCoreMLModels.loadStages(admission:)`, wired at `KokoroComposition.swift:207`) and the
  gate never opening in a background launch — **on `dev`** via PR #16 (`68233bd`);
  `ForegroundGate.swift` and `CPUBudget.swift` are identical between `dev` and the tip.
- **(b)** the `BGTaskScheduler` launch handler `{ @Sendable task in }` (`PrepareTask.swift:23`)
  — **on `dev`** via PR #16 (`21d1940`); the file is identical between `dev` and the tip.
- **(c)** MLX's process-global default device set to the CPU — `mlxPinnedToCPU`
  (`KokoroCoreMLEngine.swift:1041-1044`, forced in the engine's `init` at `:241`) — **branch
  only**, commit `072ab74`. `dev` has only the task-local `MLX.Device.withDefaultDevice(.cpu)`
  pins (`:424`, `:762`, `:796`) and a comment saying "Deliberately *not*
  `MLX.Device.setDefault`". The 21:39 and 21:54 crashes on the post-merge binary are the direct
  evidence that the task-local pin does not hold across MLX's completion handler.
- Wart for Harsh: the pre-fix comment "Deliberately *not* MLX.Device.setDefault: that is
  process-global…" survives at `KokoroCoreMLEngine.swift:1050-1052`, three lines under the code
  that now does exactly that.

So the three classes are not A19-specific. They fire in the background on the A13 — six of the
eight are Prepare launches nobody was watching, the eighth pair is the G2P fallback network on
Metal while the phone was locked — which is why the owner mostly did not see them; the 18:00
one happened in front. The one class the owner's current build still has is (c), and it is the
one this branch fixes.

**The control, run 23:00** — the owner imported the same story into `t2s`, played it, locked the
phone: *"it paused twice (no crash), first pause was early in the recording, I think the file had
not rendered, then the next was after quite some time… while the audio was playing it was good
without issues."* No new report in the crash store; the process was still alive afterwards. That
build has no per-launch timing file, so there are no numbers, but the shape is Finding 2b's:
`CPUBudget` and the 60 s play-ahead are on `dev`, and the early first pause is the sample-floor
stall (the first background wait is charged for all CPU since the last sample). The MLX crash
class did not fire in those minutes — it needs the G2P fallback network to run while
backgrounded, which depends on the text — so the A/B on class (c) is inconclusive; the 21:39 and
21:54 reports remain its evidence.

## Still owed

- ~~Harsh: the CPU-path play-ahead (150–180 s), the memory gate on the GPU override, the stale MLX comment~~ — done on `dev` (`b5b34fa`, `84e16f9`, `1c29cec`), with the owner's OK, the same night; the download is also deduplicated (`b6548e6`).

- A > 90 s manual lock during the *first* warm-up on this branch (Finding 2's residual exposure).
- The `t2s` control on class (c) specifically: a text that exercises the G2P fallback, locked long enough.
- The GPU-path lock test on a phone that can build the GPU plans (a 17 Pro).
- Map `d32acb6f…`, `3920dd54…` and `c7863998…` to commits if those builds turn up anywhere.

## Open questions for Harsh

- Did the 17 Pro's 15:23 download go through in one launch, or did it need relaunches?
- Which tier did the playback test plan under with the phone on USB? (Finding 2b's numbers say
  tier 1, but the code says charging selects tier 3.)
