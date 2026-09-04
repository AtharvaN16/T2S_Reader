# t2s_reader — hand-off and next steps

_Last updated 2026-09-03, late evening (Plan 5 Task 5 landed: the Kokoro engine, its device probe, the route and the fallback, on A14+ builds only). Written for whoever picks up the coding next._

## What this is

An iOS app that turns EPUBs, web articles, and text PDFs into read-along audiobooks
synthesized on the phone. The design spec is the source of truth:
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](superpowers/specs/2026-09-01-t2s-reader-design.md)
(rev 8). Work is organised as numbered plans under
[docs/superpowers/plans/](superpowers/plans/), each a list of tasks with the exact code, tests,
and commit message per task. The roadmap is
[2026-09-02-t2s-reader-roadmap.md](superpowers/plans/2026-09-02-t2s-reader-roadmap.md).

## Branches

| Branch | State | Notes |
|---|---|---|
| `dev` | integration branch | Plans 1–4a, Plan 4b Tasks 1–8, all of Plan 5 (Tasks 1–6), the playback crash fix, and the Plan 0 spike findings so far are merged. Plan 5 Tasks 5–6 were fast-forwarded from `plan-5-task-5-kokoro` on 2026-09-03 (`938c8b8 … ba207ed`, twelve commits, every task reviewed plus a whole-branch review). Root package: **309 tests in 72 suites** (`swift test`). `Packages/T2SKokoro`: **56 tests in 7 suites** (`scripts/test-kokoro.sh`; seven of them are gated on the real model files being installed — four load the 327 MB model and two of those synthesize audio). `Packages/T2SReadium`: **12 tests in 3 suites** (`scripts/test-readium.sh`, on the iPhone simulator). The everyday app builds, launches, imports an EPUB, and plays it on the simulator and on an iPhone 11 Pro. |
| `main` | stale: only the initial spec commit | Not used for integration yet; fast-forward it to `dev` when you want a release point. |

Plan branches are short-lived: each plan runs on its own branch off `dev` (locally in a git
worktree under `.worktrees/`, git-ignored) and is merged and deleted when its final review is clean.

## Toolchain

- Xcode 26.6 (Swift 6.2), macOS 15+. CI uses that single pinned toolchain, restores both SPM and Xcode package caches, and retries transient package resolution. `brew install xcodegen`. An iPhone simulator installed. The Plan 5 Task 5/6 pass on this branch was run locally on **Xcode 26.3** (iPhoneSimulator 26.2 SDK), not on CI's 26.6 — every build and test result quoted below is from that toolchain.
- `swift test` — the root package on macOS (everything except Readium).
- `scripts/test-readium.sh` — the iOS-only Readium package on the simulator (`SIMULATOR_ID=<udid>` to pick one).
- `scripts/build-app.sh` — regenerates `App/T2SReader.xcodeproj` from `App/project.yml` and builds the app for the simulator. Then `open App/T2SReader.xcodeproj` to run it.
- `scripts/check-licenses.sh` — fails on any copyleft dependency (CI runs it).
- `scripts/fetch-kokoro-model.sh` — installs the Kokoro weights and voice styles into
  `App/Resources/Kokoro` (git-ignored, checksum-verified). Run it once per machine; without it the
  model-backed package tests skip and a device build bundles no voices.
- `scripts/test-kokoro.sh` — `Packages/T2SKokoro` with `xcodebuild` on macOS. Not `swift test`: MLX
  loads a compiled Metal library that only a full Xcode build stages next to the binary. Runs
  `-parallel-testing-enabled NO` on purpose (see the script header).
- `scripts/build-device.sh` — Release, `generic/platform=iOS`, unsigned: the compile proof for the
  `T2SReaderKokoro` target. The first run compiles mlx-swift for iphoneos (10–15 min, ~2 GB).

CI runs the test and build scripts (not the fetch ones): a `kokoro-macos` job for
`scripts/test-kokoro.sh`, added by Task 5a with a 45-minute timeout, and an `app-ios` job that runs
`scripts/build-app.sh` then `scripts/build-device.sh` — its timeout went 30 → 45 minutes because it
now compiles MLX for iphoneos on a cold cache. The model files are absent in CI, so the
model-backed Kokoro tests report as skipped there.

Never commit generated files (`*.xcodeproj`, `App/T2SReader/Info.plist`, `App/T2SReader/Info-Kokoro.plist`, `.build/`); one `.gitignore` at the root.

## What exists

Everything here is on `dev`.

- **T2SCore** — text pipeline: normalizer with span mapping, sentence segmenter, two-phase timeline (estimated → actual durations), per-chapter codec, `Position` resolution, highlight projection, render policy tiers, render scheduler, audio cache with LRU. Plan 1 + Plan 2.
- **T2SAudio** — `AudioPlayer` on `AVAudioEngine` with pitch-corrected rate, `PlaybackCoordinator` (owns the playhead), `AACCodec`, and `SystemSpeechEngine` (AVSpeechSynthesizer; the engine until Kokoro lands). Plan 2 + Plan 4a.
- **T2SStore** — SwiftData store (`LibraryStore`): documents, per-chapter timeline blobs, queue order, resume positions as flattened columns, bookmarks, pronunciation dictionary; versioned schema; `PlayheadStore` conformance. Plan 3.
- **T2SLibrary** — `Library` facade (import file / article, delete, re-derive stale timelines, evict audio), `PDFDocumentReader` (PDFKit), stored-only ZIP writer, `ArticleEPUBWriter`, container layout `LibraryPaths`. Plan 3.
- **Packages/T2SReadium** (iOS only) — `ReadiumDocumentReader` (EPUB → chapters with stable `Position`s) and `LocatorMapping` (`Position` ↔ Readium `Locator`, word-highlight quotes). Plan 3.
- **T2SApp** (root package target, testable on macOS) — the app's models: `LibraryModel`, `PlayerModel`, `ScrubberModel`, `ImportModel`, `DurationFormatter`, `AppPaths`, `DeviceStateMapping`. Plan 4a.
- **App/** — the SwiftUI app `T2SReader`: design tokens and type roles (Inter, bundled), composition root, three-page pager with mini-player, Queue page, Collection page + book sheet, player sheet with the tick scrubber, Add sheet (paste a link → WKWebView + Readability.js extraction preview, open a file, paste text), audio session + device monitor. Plan 4a. Plan 5 added the Now Playing controller and remote commands, Preferences → Cloud voices, the Prepare task boundary, and the `T2SReaderShare` Share Extension.
- **Packages/T2SKokoro** (tested on macOS, links only into the device target) — `KokoroResources`
  (the checksummed model-file contract), `KokoroEngine` (an actor over kokoro-ios/MLX; identity
  `kokoro-4e9ecdf0-mlx-misaki1.0.6`), `KokoroTokenTimingMapper`, `KokoroRuntimeDecision` and
  `KokoroAvailability`. Plan 5 Task 5.
- **Packages/MLXUtilsLibrary** — a vendored copy of `mlalma/MLXUtilsLibrary` 0.0.6 with our own
  `NpzArchive` in place of ZIPFoundation. Plan 5 Task 5; see "Known issues" for why and for the
  exit plan.

## Where things are right now

The integration branch carries Plan 5 in full: its last commit, `ba207ed`, sits on top of
`153af2a` (the approved Task 5 adjustments) and `499d3fa` (the spike findings and the PR #14/#15
merges). The completed work is:

- **Plan 4a** is complete.
- **Plan 4b Tasks 1–8** are merged: PR #2 (Reader models and preferences), PR #3 (pronunciation,
  storage, and voice-change models), PR #4 (Reader and appearance UI), and PR #7 (Preferences and
  voice-change UI). PR #10 is the Reader review-fix wave; PR #11 is the Preferences review-fix wave.
  They include safe destructive audio-change APIs, no-op unchanged voices, session-owned voice
  previews that stop on disappearance, robust Readium/PDF handling, and publication cleanup.
- **Documentation and CI**: PR #5 documented the Reader controls; PR #6 made CI deterministic on a
  single Xcode 26.6 toolchain and added SPM/Xcode package caches plus package-resolution retries.
- **Plan 5** is written in PR #8. Task 1 (Now Playing, remote controls, and media-services recovery)
  merged in PR #9, Task 3 (multi-document Prepare and `BGProcessingTask`) in PR #12, Task 4
  (BYO-key cloud engine) in PR #13, and Task 2 (Share Extension) in
  [PR #15](https://github.com/AtharvaN16/T2S_Reader/pull/15).

The app has been built and launched on the simulator. CI reruns every script below on each push.

**Plan 5 Task 5 (Kokoro) landed on `plan-5-task-5-kokoro`, commits `938c8b8 … 647fad6`**, in the
order the approved "Task 5 adjustments" set out. What is now in the tree:

- `Packages/T2SKokoro`: `KokoroResources` (the checksummed model contract), `KokoroEngine` (an
  actor; `identity` = `kokoro-4e9ecdf0-mlx-misaki1.0.6`), `KokoroTokenTimingMapper` (returns `[]`
  until the 17 Pro fixture exists), `KokoroRuntimeDecision` (`current == nil`; a `DEBUG`-only
  override), `KokoroAvailability` + `KokoroAvailabilityModel`.
- Root package: `KokoroVoiceID`, the `kokoro:` route in `RoutedEngine`, the `VoiceRouteResolving` /
  `KokoroVoiceRouting` seam that substitutes the whole document's voice *before* planning,
  `VoiceOption.group`, `KokoroVoiceCatalog` (28 voices, cross-checked against `voices.npz`), and
  the `NumberWords` compound-number spacing fix with a normalizer version bump. **That bump has an
  upgrade cost:** `Versions.normalizer` becomes 2, so on first play every document already in a
  library is stale — it is re-normalized and re-segmented (spec §3.7.3), and the audio rendered
  under normalizer 1 becomes orphaned cache that only LRU pressure removes. Positions survive:
  `PositionResolver` re-resolves them against the new segmentation.
- App: **two targets from one xcodegen template** — `T2SReader` (simulator and any phone, no MLX)
  and `T2SReaderKokoro` (`SUPPORTED_PLATFORMS: iphoneos`, links the engine, compiles with
  `KOKORO_ENGINE`). `KokoroComposition` is the only `#if`. Preferences → Voice shows a "Kokoro
  (beta)" section with an availability footer. New scripts `fetch-kokoro-model.sh`,
  `test-kokoro.sh`, `build-device.sh`; `build-app.sh` now signs ad hoc locally.
- Why two targets: mlx-swift 0.30.2 cannot link for the iOS Simulator — the iPhoneSimulator SDK's
  Metal framework does not export `_MTLIOErrorDomain` / `_MTLTensorDomain`, on both architectures —
  and Xcode resolves packages per project, not per target.

**Plan 5 Task 6 is this documentation commit.** The whole suite is green on this branch:
`swift test` 309 tests / 72 suites; `scripts/test-kokoro.sh` 56 tests / 7 suites
(`** TEST SUCCEEDED **`); `scripts/test-readium.sh` 12 tests / 3 suites (`** TEST SUCCEEDED **`, on
the iPhone simulator); `scripts/check-licenses.sh` exit 0; `scripts/build-app.sh` and
`scripts/build-device.sh` both `** BUILD SUCCEEDED **`.

**Real Kokoro synthesis has run — on this Mac, not on a phone.** Task 5b's model-backed test
synthesized one 3.25 s sentence with `af_heart`: model load 1.14 s and RTF 0.456 warm; 1.54 s /
RTF 1.633 cold, with Metal kernel compilation inside that first call. These are Mac numbers and
set no thresholds; they do suggest a warm-up synthesis may be worth it on device, since the first
utterance pays the kernel compile.

**Playback crash, found and fixed 2026-09-03 (afternoon).** Playing any document crashed the app
(`EXC_BREAKPOINT` on MediaPlayer's `accessQueue`) the moment `MPNowPlayingInfoCenter` pushed the
first Now Playing dictionary: the `MPMediaItemArtwork` request handlers were formed inside the
`@MainActor` `NowPlayingController`, so Swift 6 inferred main-actor isolation and inserted an
executor check that MediaPlayer's queue fails. Nobody had played a document on an iOS runtime
before (Task 9 was never run), which is how it survived. Reproduced on the iPhone 16 Pro
simulator; the five crash reports later pulled off the iPhone 11 Pro (iOS 26.6.1) with
`xcrun devicectl device copy from --domain-type systemCrashLogs` carry the identical frames. Fixed
(merged to `dev` as 2540e1c, confirmed on the phone):
`NowPlayingArtwork.make(_:)` in `T2SApp` forms the handler in a nonisolated context, with a test
that calls it from a global queue. After the fix an EPUB was imported through `onOpenURL` and
played in the Reader for 45 s+ on the simulator without incident.

## Manual validation matrix

Nothing below was run on a phone for this commit: no device is attached to this Mac and the
iPhone 17 Pro is Harsh's. Every row says what the *best available* evidence actually is. A row
marked **pending hardware** has never run on a device — treat it as untested, not as a footnote.

| Scenario | Best evidence today | Status |
|---|---|---|
| Kokoro whole-document fallback in a build without the engine | iPhone 16 Pro simulator, iOS 18.5 (Task 5f): the log carries `Kokoro engine not linked in this build` and `voice route fallback: kokoro → default` while the Reader plays; no `KokoroRouteError` and no render error in the 37 s to the screenshot | **passes (simulator)** |
| Kokoro synthesizes real audio through kokoro-ios/MLX | this Mac (Task 5b + `scripts/test-kokoro.sh`): seven tests are gated on the real files, four of them load the 327 MB model and `voices.npz`, and two synthesize audio; one 3.25 s sentence at RTF 0.456 warm | **passes (macOS)** |
| `T2SReaderKokoro` links MLX, embeds `KokoroSwift.framework`, bundles the ~342 MB of model files | `scripts/build-device.sh` — `** BUILD SUCCEEDED **`; `Frameworks/` contains `KokoroSwift.framework` and `otool -L` resolves into the bundle. The spike harness's missing-framework gotcha does not reproduce for this target | **passes (compile + link)** |
| The `.available` / `.unavailable(reason)` Preferences footer strings, and `GatedKokoroEngine`'s construction path | compiled only. On a simulator the probe answers `.unavailable(.simulator)` before any GPU check, and the everyday target does not link the engine, so neither has ever executed | **pending hardware** |
| Now Playing dictionary pushed without crashing | iPhone 11 Pro, iOS 26.6.1: the artwork main-actor crash was reproduced there and the fix (`2540e1c`) confirmed on the phone | **passes (hardware, this path only)** |
| Lock Screen and Control Center transport controls | Plan 5 Task 1 verified the software seams (PR #9) | **pending hardware** |
| AirPlay route selection | — | **pending hardware** |
| Wired route change (headphones unplugged mid-playback) | — | **pending hardware** |
| Bluetooth route change (AirPods connect / disconnect) | — | **pending hardware** |
| Phone-call interruption and resume | — | **pending hardware** |
| `mediaServicesWereReset` recovery (force it from the debugger) | PR #9 seams only | **pending hardware** |
| Share sheet payloads: link, plain text, EPUB, PDF — and each failure string | Task 2 merged in PR #15; import through `onOpenURL` works on the simulator | **pending hardware** |
| App-group hand-off: extension writes `ShareInbox`, host finishes the import | the entitlement is why `scripts/build-app.sh` now signs ad hoc, and the ad-hoc-signed simulator app does open its library | **pending hardware** (partial) |
| Prepare stops on unplug, Low Power Mode, and thermal pressure | Plan 5 Task 3 (PR #12) verified the runner and the visible state on a simulator | **pending hardware** |
| `BGProcessingTask` forced from the debugger | the simulator rejects the request outright — `BGTaskSchedulerErrorDomain error 1`, seen again in the Task 5f capture | **pending hardware** |
| `BGProcessingTask` overnight on charge | — | **pending hardware** (§7.7 asks for three nights) |
| Cloud voice: missing key, 401, 429, network loss, configuration change | Plan 5 Task 4 (PR #13) unit coverage inside `swift test` | **pending hardware** — no real provider key has been exercised end to end |
| Plan 0 Kokoro metrics §7.3, §7.4, §7.5 — Core ML route | iPhone 11 Pro (A13): CPU-only Core ML, RTF 0.18 flat out and 0.16 over 20 min at 4x, 119 MB flat, word-onset error ≤ 55 ms; thermal state 2 after 150 s at 4x on charge with no speed collapse (`spikes/findings/2026-09-04-pre-a14-runtime.md`) | **passes (hardware)**; unplugged thermal/battery run pending |
| Plan 0 Kokoro metrics §7.2, §7.3, §7.5, §7.7 — MLX route | needs an A14+ phone; nothing measured | **pending hardware** (the 17 Pro, protocol below) |

## The iPhone 17 Pro run (for Harsh)

Two halves. The **spike harness** produces the Plan 0 numbers; the **app** proves the shipped route
end to end. Do the harness first — its CSV is what unblocks the code.

**1. The spike harness.** `spikes/README.md` is the complete protocol: the exact `xcodebuild` /
`devicectl` commands, the launch environment for each spec section (§7.3/§7.5 `SPIKE_AUTORUN_SECONDS=300`
at rate `0`, then `1200` at rate `3` for thermals; §7.2 with `SPIKE_BACKGROUND_AUDIO=1` for 15
minutes screen-off, repeated in Low Power Mode; §7.7 three nights on charge), how to pull the CSV
back, and every tooling gotcha — Release with `ENABLE_DEBUG_DYLIB=NO`, the `KokoroSwift.framework`
copy-and-re-sign step, the free-team three-app limit, and which of the two device identifiers each
tool wants. Write one findings file per section into `spikes/findings/` from `TEMPLATE.md`.

**2. The app.** This is what has never run:

```
scripts/fetch-kokoro-model.sh          # first, or the build bundles no voices
open App/T2SReader.xcodeproj           # generated by scripts/build-app.sh or scripts/build-device.sh
```

- Scheme **`T2SReaderKokoro`** (not `T2SReader`). It is device-only by design; the simulator cannot
  link MLX.
- Signing & Capabilities → your own team, on **both** `T2SReaderKokoro` and `T2SReaderShare`. The
  app group `group.com.t2s.reader` must stay on both or the app cannot open its library. A free
  personal team allows three apps on a device and an app with an extension counts twice.
- Edit Scheme → Run → Arguments → Environment Variables: `T2S_KOKORO_DEBUG_OVERRIDE` = `1`. Without
  it `KokoroRuntimeDecision.current` is `nil`, the route reports itself unavailable, and every
  document falls back to the system voice — which is correct behaviour, just not what you want to
  test. (The `kokoro.debugOverride` user default does the same thing.) The override is compiled out
  of Release builds and labels itself in the Preferences footer as "development override". With the
  override on, Kokoro also runs in Prepare and in background play-ahead — that is the §7.2/§7.7
  experiment, not an enforced policy yet: the decision's `backgroundInferencePermitted` and
  `idleInferencePermitted` flags are recorded but read nowhere.
- Build and run on the phone from Xcode. `scripts/build-device.sh` builds the same target unsigned
  from the command line — useful for a compile check, useless for installing.
- In the app: Preferences → Voice → the **Kokoro (beta)** section. Read the footer first; it should
  say the route runs on this device. Pick a Kokoro voice, then play a book and let it run.
- What to report back: does the footer say available; does the first sentence play; how long the
  first utterance takes versus later ones (MLX compiles Metal kernels during the first synthesis);
  whether the read-along highlight tracks (it will be sentence-level — word timings are still `[]`);
  and anything in the log under subsystem `com.t2s.reader`.

If a `devicectl` install is used instead of Xcode, build Release with `ENABLE_DEBUG_DYLIB=NO` —
Xcode's debug-dylib layout leaves the package frameworks in DerivedData and the installed app
aborts at launch with `Library not loaded: @rpath/KokoroSwift.framework`. The app target itself
does embed `KokoroSwift.framework` correctly, so the spike harness's manual copy-and-re-sign step
is **not** needed here.

## Resume here (2026-09-04)

Plan 6 (`docs/superpowers/plans/2026-09-04-plan-6-coreml-kokoro-engine.md`, the Core ML Kokoro engine) is
**in progress on branch `plan-6-coreml-engine`**, checked out in the git worktree
`.worktrees/plan-6-coreml-engine` (the directory may still be named `plan-7-coreml-engine` on the
machine that started it; `git worktree list` tells). Tasks 1–3 are committed and reviewed: the
vendored `Packages/KokoroPipeline` and `scripts/fetch-kokoro-coreml.sh --app` (Task 1); the Core ML
resources contract, the measured A13 decision and the tokenizer (Task 2); `KokoroCoreMLEngine` with
real word timings, chunking of utterances longer than the pipeline's 15 s bucket, and the §7.4 timing
gate opened in `KokoroTokenTimingMapper` (Task 3, `scripts/test-kokoro.sh` 80+ tests green).
**Resume at Task 4** (availability, multi-engine routing, Kokoro Heart as the default voice) with
superpowers:subagent-driven-development. The ledger with every ruling so far is
`.superpowers/sdd/2026-09-04-plan-6-coreml-kokoro-engine/progress.md` inside that worktree. Run
`scripts/fetch-kokoro-coreml.sh --app` once on a new machine before the model-backed tests. Two
things learned in Task 3: the engine's development path (`.mlpackage` staging, used by the tests)
compiles the eight stages into `/var/folders/…/T` on every engine instance and never removes them —
repeated test runs filled this Mac's disk (4.7 GB found and deleted); the app bundle is precompiled
and unaffected. And `preload()` is `async` and its compile is shared, so a render cancelled during a
cold load waits the compile out rather than returning promptly.

## What comes after

The product owner decided on 2026-09-03 that Kokoro is the app's main engine (the system voice is
a placeholder). Task 5 has since shipped everything that does not depend on a measurement, so what
remains is the measurement itself.

1. **Plan 0 measurements on the iPhone 17 Pro (Harsh).** The plan is
   [2026-09-02-plan-0-spikes.md](superpowers/plans/2026-09-02-plan-0-spikes.md); the exact no-taps
   command-line protocol and every tooling gotcha are in `spikes/README.md`. Done so far:
   - §7.1 (`spikes/findings/2026-09-03-g2p-coverage.md`): all Kokoro-path licences permissive
     (MisakiSwift is Apache-2.0, not MIT); MisakiSwift accepted as the only G2P, English-only, with
     two mitigations (join compound numbers with a space in `NumberWords`; heteronyms lack POS).
   - §7.3/§7.5 on the iPhone 11 Pro (`2026-09-03-runtime-benchmark.md`): **kokoro-ios/MLX cannot
     run on the A13** — MLX's steel GEMM needs `simdgroup_matrix` (Apple GPU family 7, A14+), so
     the first `generateAudio` traps. The MLX route has an A14 floor.
   Pending, all on the 17 Pro: §7.3/§7.5 (one 5-minute run + a 20-minute 3x run), §7.4 (the three
   WAVs from that run against the CSV `timing` rows), §7.2 (15 minutes screen-off with
   `SPIKE_BACKGROUND_AUDIO=1`), §7.7 (three overnight runs). Findings go in `spikes/findings/`
   and a `RESOLVED` line under each spec §7 subsection. The app half of that visit is written out
   under "The iPhone 17 Pro run" above.
2. **Wire the 17 Pro numbers into the code.** The engine, probe, route, catalog, fallback and UI
   all exist (Plan 5 Task 5); only the measured constants are missing. When the findings files
   land, in this order:
   - Fill `KokoroRuntimeDecision.current` from the finding file — measured RTF, the rate threshold
     derived from it, and the memory limits. It is `nil` today and the engine refuses to be
     selected while it is; there is a `DEBUG` override precisely so nobody is tempted to guess.
     `debugOverride` is the shape the real value must take.
   - Wire `backgroundInferencePermitted` into the render policy and `idleInferencePermitted` into
     `PrepareRunner` / `PrepareTask`. Neither flag is read anywhere today: they are recorded on the
     decision and nothing consumes them, so filling `current` alone does **not** enforce the
     §7.2/§7.7 policy — a decision that says "no background inference" would still render in the
     background. Do this before, or with, the fill.
   - Add the `RESOLVED` lines under spec §7.2, §7.3, §7.4, §7.5 and §7.7, each pointing at its
     findings file, the way §7.1 and §7.6 read now.
   - Write the `KokoroTokenTimingMapper` fixture from the CSV's `timing` rows, then make the mapper
     return real word timings. Two caveats the Task 5b review recorded, both to be settled against
     the fixture rather than by reasoning: (a) `candidateTimings` does not advance `searchFrom`
     past a skipped token, so adjacent repeated words can bind to the wrong range; (b)
     `MToken.tokenRange` may be a better alignment source than searching the text at all.
   - Then consider making a Kokoro voice the default. It is a product decision, not a mechanical
     one: it changes every render key, so cached audio is re-derived (spec §3.7.3), and it only
     applies to A14+ phones.
3. **Plan 0 Task 8 — DONE (2026-09-04): Core ML is the Kokoro runtime, and it runs on the
   iPhone 11 Pro.** `spikes/findings/2026-09-04-pre-a14-runtime.md`: `mattmireles/kokoro-coreml`'s
   `KokoroPipeline` (Apache-2.0) with **every stage on the CPU** gives median RTF 0.18 flat out and
   0.16 over 20 minutes at 4x on the A13, a flat 119 MB footprint, and word-onset timing within
   55 ms — so every rate up to 4x is offered and the rate-cap / prepare-the-whole-book idea is not
   needed on this phone (it stays the design for any slower device). The GPU-assisted policy is
   slower there (0.37) and needs 1.2 GB; MLX on the CPU is dead (RTF 15). Open follow-ups: the
   unplugged 20-minute run for thermal/battery numbers (state 2 was reached on charge at 4x
   without any speed collapse), and the word-end fold fix (trailing pause belongs to the
   punctuation). The desk research behind the choice is
   `spikes/findings/2026-09-03-pre-a14-runtime-options.md`; the harness arm and its fetch script
   are `spikes/SpikeHarness/SpikeHarness/CoreMLBench.swift` and `scripts/fetch-kokoro-coreml.sh`
   (see `spikes/README.md`, "Core ML arm", for the stale-manifest fix and the launch switches).

   **Owner's direction (2026-09-04):** Core ML becomes the engine in the app, on every phone, and
   newer phones get whichever architecture measures best there. **This is the next code task**
   (a plan of its own, ahead of items 1–2): a `KokoroCoreMLEngine` beside the MLX one in
   `Packages/T2SKokoro` — the pipeline package vendored like MLXUtilsLibrary (the upstream repo
   root has no `Package.swift`; the package is its `swift/` subdirectory), the four fp16 stages
   per bucket fetched with checksums and bundled, `.mlmodelc` precompiled by Xcode, the token
   path (MisakiSwift → Kokoro vocab → ids) and the per-word timing fold ported from the harness,
   engine identity `kokoro-coreml-<hf revision>-cpu-misaki1.0.6`, the availability probe taking the
   Core ML branch on every device (CPU-only compute units until an A14+ measurement says
   otherwise), a first-launch compute-plan warm-up (the very first load took 206 s on the A13;
   later loads take 3–5 s) shown as a one-time "preparing the voice" state rather than a hang,
   `KokoroRuntimeDecision` filled from the A13 finding for the Core ML route, and Kokoro as the
   default voice. Core ML also runs in the simulator, so this engine belongs in the everyday
   `T2SReader` target and makes Kokoro testable on the Mac; `T2SReaderKokoro` (MLX) stays for the
   17 Pro measurement only.
4. **The hardware matrix above.** Every row marked *pending hardware* — the Lock Screen and route
   changes, the Share Extension payloads, Prepare's power and thermal stops, `BGProcessingTask`,
   and the cloud error paths — plus Plan 4b Task 9's remaining EPUB/PDF fixture and UI test. A
   failing row is a fix round, not a footnote.
5. **Plan 7** (renumbered 2026-09-04; Plan 6 is now the Core ML engine) is unchanged: CloudKit sync behind `SyncProvider`, Live Activity, App Intents, and
   Spotlight. Its constraints from Plan 5: sync stays behind `SyncProvider`; the app-group store is
   the only local source of truth; a Live Activity or App Intent may *read* `NowPlayingSnapshot` /
   `PlayerModel` but must not become a second playback owner; CarPlay stays deferred even though
   the MediaPlayer remote commands now work.

## Known issues and parked items

1. **Plan 4b Task 9 is open:** the EPUB read-along has now passed once on the simulator (see
   above), but the pass on hardware, the EPUB/PDF fixture, and the UI test are still not done.
   A usable fixture already sits in Readium's checkout
   (`Tests/Publications/Publications/childrens-literature.epub` under `swift-toolkit`).
2. ~~**`scripts/build-app.sh` produces an app that cannot open its library.**~~ **Fixed** in Task 5f:
   the script now signs ad hoc locally (`CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO
   CODE_SIGN_IDENTITY=-`) and stays unsigned only under `CI`, so the simulator app gets the
   `application-groups` entitlement and opens its library. Kept here because the symptom — "The
   library could not be opened." — is what you see if that signing is ever removed again.
3. **Physical-device validation remains open:** audio through phone-call interruption and AirPods
   route changes; Lock Screen and Control Center controls; and debugger-forced
   `mediaServicesWereReset` recovery. PR #9 verified the software seams, not these hardware paths.
   The matrix above is the full list.
4. **Background processing remains device-only:** PR #12 verified the runner and visible state on a
   simulator, but the simulator rejects the opportunistic request outright
   (`BGTaskSchedulerErrorDomain error 1` — expected there, not a bug). Validate `BGProcessingTask`
   scheduling and a simulated launch while the device is on charge.
5. **Share Extension remains unverified on hardware:** Task 2 merged in PR #15. Verify the share
   sheet on a physical device for link, text, EPUB, and PDF input, each failure string, and the
   app-group hand-off into the host.
6. **Kokoro's gate is half open.** §7.1 is resolved and the MLX route is known to need A14+; the
   17 Pro numbers (§7.2–§7.5, §7.7) still decide the rate threshold, memory limits, background
   policy, and whether word timings can drive the highlight. The engine, probe, route, catalog and
   fallback all landed in Task 5 with **no guessed constants**: `KokoroRuntimeDecision.current` is
   `nil`, `KokoroTokenTimingMapper` returns `[]`, and the default voice stays the system voice. The
   iPhone 11 Pro cannot run this route at all (Plan 0 Task 8).
7. **A Kokoro engine failure after the probe has passed leaves the book playing silence.** The
   availability probe runs once, at configuration time (adjustment 3 scopes the fallback there), so
   a failure inside `KokoroEngine.load()` or `generateAudio` — a corrupted weight file, an MLX
   allocation failure, jetsam pressure — throws per utterance from then on. The coordinator does
   what spec §6 asks: it surfaces the message as `lastRenderError` and fills 200 ms of silence, so
   the book does not halt. But there is no re-route after the probe, so it plays silently with an
   error showing until the reader changes the voice by hand. Follow-up: on the first
   `KokoroEngineError` out of `GatedKokoroEngine`, flip `KokoroAvailabilityModel` to unavailable
   (a new reason, e.g. `.engineFailed`) so the next load falls back to the system voice and the
   Preferences footer says why.
8. **`Packages/MLXUtilsLibrary` is vendored, and SwiftPM warns about it on every resolve.**
   `readium/ZIPFoundation` (3.0.1+, via the Readium toolkit) and `weichsel/ZIPFoundation` (0.9.x,
   via `kokoro-ios` → `MLXUtilsLibrary`) share the SwiftPM identity `zipfoundation` with disjoint
   version ranges, so adding Kokoro to the app project broke resolution for the *whole* project —
   `xcodebuild -list` failed. The fix (Task 5f) vendors `MLXUtilsLibrary` 0.0.6 (Apache-2.0, ~64 KB
   of Swift, revision `41f6cfd5`) as a local package with its one ZIPFoundation call replaced by
   our own `NpzArchive` — a stored+deflate npz reader on the Compression framework. Zip leaves the
   Kokoro path entirely; Readium is untouched. **The accepted cost:** the local package's identity
   `mlxutilslibrary` overrides the remote that both `kokoro-ios` and `MisakiSwift` reference, so
   SwiftPM prints, twice per resolve, `Conflicting identity for mlxutilslibrary … This will be
   escalated to an error in future versions of SwiftPM`. If a future Xcode makes good on that, the
   app build breaks — not just the Kokoro path. **Exit plan:** open a PR against MLXUtilsLibrary
   dropping ZIPFoundation (it is used for exactly one call, `Archive(data:accessMode:pathEncoding:)`
   in `NpyzReader.swift`); once that is released and `kokoro-ios` picks it up, delete
   `Packages/MLXUtilsLibrary` and go back to the remote. The fallbacks if that stalls are an
   owner-hosted fork or prebuilt XCFrameworks, both costed in `task-5f-report.md`.
9. **The full suite needs disk, and this machine keeps running out.** A cold `scripts/test-kokoro.sh`
   or `scripts/build-device.sh` compiles mlx-swift (~2 GB); `scripts/test-readium.sh` resolves the
   Readium toolkit (~1 GB). Reclaim before a cold run rather than during one: `.build` (~4 GB here,
   SwiftPM output plus `DerivedData-App`), `Packages/T2SKokoro/.build` and
   `Packages/T2SReadium/.build` all regenerate from the scripts that use them.
10. **Deferred minors from the Task 5 reviews**, in the order a reader is likely to hit them:
    - `VoiceListPage` maps the `.notLinked` status to "Checking this device…" — unreachable in
      either shipped target, but the wrong text if it ever is reached.
    - A `kokoro:`-prefixed voice ID that fails to parse passes the route resolver and falls through
      `RoutedEngine`'s bare-ID path to the system engine silently. Only reachable from a corrupted
      row; it should throw `KokoroRouteError`.
    - Fallback-rendered audio is keyed to `"default"` and is not evicted when Kokoro later becomes
      available, because the stored `document.voiceID` never changed. Left to size-managed eviction.
    - `NpzArchive` does not check the walked entry count against the EOCD total, and allocates
      whatever uncompressed size an entry header declares before bounds-checking it. It only ever
      reads a checksum-verified file we ship.
    - `KokoroResources.Located`'s public memberwise init lets a caller bypass `locate()`'s size gate;
      `KokoroAvailability`'s catch-all reports the model file's name even when `voices.npz` was the
      file that failed to read; `MLX.Memory.cacheLimit` is process-global and the test that sets it
      never restores it.
    - Three mlx-swift manifest warnings are visible in `scripts/test-kokoro.sh` output. They are
      upstream and carry no path, so the script's checkout filter cannot catch them.
    - Readium's pre-existing `GCDHTTPServer` deprecation warnings now also surface in CI's device
      build step.

Other retained review items:
- Same bug class as the artwork crash, unproven: `MainActor.assumeIsolated` inside the
  `MPRemoteCommand` handlers in `NowPlayingController.start()` and in the `deinit`s of
  `NowPlayingController` and `AudioPlayer`. They hold as long as MediaPlayer delivers commands on
  the main thread and those objects are only ever released on it; the Lock Screen / AirPods pass on
  hardware is where they would show.
- No app icon / asset catalog yet — blocking for TestFlight, fine for development.
- `LibraryModel` progress is still computed per queued document on refresh (cached per summary);
  lazy per-row computation and an explicit, cancellable stale-timeline migration are the next step
  if the library grows large.
- Test temp directories under `t2s-app-<uuid>` are not removed after the suite.
- `LocatorMapping.locator(for:)` defaults the media type to XHTML; PDF positions need `.pdf`.
- `Library.store` is public, so the facade can be bypassed; `Library.delete` is not idempotent.
- PDF: outline traversal is top-level only; `PDFCover` upscales narrow pages.
- `PlaybackCoordinator.fill()` runs outside its serial chain (a seek during a fill can leave a stale clip); the ~76 ms time-pitch look-ahead is a calibration item (`AudioPlayer.outputLatencySeconds`); `TimeIndex` is rebuilt on every `.rendered` event; a `.failed` event without a `.rendered` leaves `.catchingUp` with no UI escape.

## Working conventions

- Every plan task ends with its own commit using the message given in the plan; tests first, then code.
- Keep `Position` as the only persisted location; never persist utterance indices or Readium types.
- Tokens only in views (no literal colors), one `accent` element per screen, no cards or dividers.
- Run `swift test` and `scripts/build-app.sh` before every commit that touches the app;
  `scripts/test-readium.sh` when `Packages/T2SReadium` changes; `scripts/test-kokoro.sh` when
  `Packages/T2SKokoro` or `Packages/MLXUtilsLibrary` changes, and `scripts/build-device.sh` when
  anything the Kokoro target links changes.
- Commit trailer used for AI-written commits: it depends who wrote them. `Co-Authored-By: Codex
  <noreply@openai.com>` through `c533290`, the last commit written by that tool;
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` from `2540e1c` onward, which is where
  the switch happened on `dev` — not at the start of this branch. Merge commits carry no trailer.
  Match whichever tool you are actually using.
- Two app targets now come from one `targetTemplates` entry in `App/project.yml`. Anything that
  applies to the app — a setting, a source path, an entitlement — belongs in the template, or the
  two targets drift apart silently.
