# t2s_reader — hand-off and next steps

_Last updated 2026-09-04 (Plan 6 is finished on `plan-6-coreml-engine` and not yet merged: a Core ML Kokoro engine with real word timings, multi-engine routing, and Kokoro Heart as the default voice on the phone build). Written for whoever picks up the coding next._

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
- `scripts/fetch-kokoro-coreml.sh --app` — stages the Core ML Kokoro model files (8 `.mlpackage`
  stages, 28 English voices, 2 runtime JSONs; 54 files, 347 MB) into `App/Resources/KokoroCoreML`
  (git-ignored, sha256-verified). Run it once per machine: it is what the default voice needs.
- `scripts/fetch-kokoro-model.sh` — installs the MLX Kokoro weights and voice styles into
  `App/Resources/Kokoro` (git-ignored, checksum-verified). Run it once per machine if you are
  working on the MLX route; without it the MLX package tests skip and a device build bundles no
  MLX voices. The app does not need it.
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
Plan 6's rows say **pending the owner's listen**: the code is built and the app bundle inspected,
but nothing on that branch has been installed on the owner's iPhone 11 Pro. The recipe for that
install is under "Resume here" below, and it is the last thing between Plan 6 and a merge.

| Scenario | Best evidence today | Status |
|---|---|---|
| Kokoro whole-document fallback in a build without the engine | iPhone 16 Pro simulator, iOS 18.5 (Task 5f): the log carries `Kokoro engine not linked in this build` and `voice route fallback: kokoro → default` while the Reader plays; no `KokoroRouteError` and no render error in the 37 s to the screenshot. Plan 6 renamed that line — it now reads `voice route resolved: kokoro → default`, because it fires on the happy path too | **passes (simulator)** |
| Kokoro synthesizes real audio through kokoro-ios/MLX | this Mac (Task 5b + `scripts/test-kokoro.sh`): seven tests are gated on the real files, four of them load the 327 MB model and `voices.npz`, and two synthesize audio; one 3.25 s sentence at RTF 0.456 warm | **passes (macOS)** |
| `T2SReaderKokoro` links MLX, embeds `KokoroSwift.framework`, bundles the ~342 MB of model files | `scripts/build-device.sh` — `** BUILD SUCCEEDED **`; `Frameworks/` contains `KokoroSwift.framework` and `otool -L` resolves into the bundle. The spike harness's missing-framework gotcha does not reproduce for this target | **passes (compile + link)** |
| `T2SReaderKokoro` bundles the Core ML stages | `scripts/build-device.sh` — `** BUILD SUCCEEDED **`; the built `.app` carries the eight `.mlmodelc` bundles, the 28 `*.bin` voices and both runtime JSON files at its root and weighs 433 MB with no MLX weights staged (Plan 6 Task 5) | **passes (compile + bundle)** |
| Core ML Kokoro speaks by default on a fresh document | wired in Plan 6 Tasks 4–5 and covered by root-package tests; no phone has played it | **pending the owner's listen** |
| The first-launch warm-up footer, and how long it stays up | the string is compiled in; the 206 s it warns about is the A13 spike harness, not this app | **pending the owner's listen** |
| Read-along highlight follows the Core ML word timings | Task 3's fold is unit-tested against synthetic frames and the §7.4 gate is open; nothing has watched a highlight move | **pending the owner's listen** |
| 2x and 4x offered, and 4x sustained | `maxSustainableRate` is 4.0, derived from the measured RTF 0.181; the derivation is tested, the playback is not | **pending the owner's listen** |
| The `.available` / `.unavailable(reason)` Preferences footer strings, and `GatedKokoroEngine`'s construction path | compiled only. On a simulator the probe answers `.unavailable(.simulator)` before any GPU check, and the everyday target does not link the engine, so neither has ever executed | **pending hardware** |
| Now Playing dictionary pushed without crashing | iPhone 11 Pro, iOS 26.6.1: the artwork main-actor crash was reproduced there and the fix (`2540e1c`) confirmed on the phone | **passes (hardware, this path only)** |
| Lock Screen and Control Center transport controls | Plan 5 Task 1 verified the software seams (PR #9); step 7 of the first listen below covers them on the Kokoro build | **pending hardware** |
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
| Bookmarks: add in Player/Reader, list in Book sheet and overflow, jump, swipe-delete | wired in Plan 8 Tasks 2–3; `BookmarkListModelTests`/`BookmarkSnippetTests` cover the model, the Book sheet section is hidden until a document has a bookmark, `scripts/build-app.sh` — `** BUILD SUCCEEDED **`; nobody has tapped it | **pending simulator** |
| App icon on the home screen | `scripts/make-app-icon.swift` draws it deterministically (byte-identical shasum across two runs), `Assets.car` is produced and `CFBundleIconName` resolves to `AppIcon` in the built Info.plist (Plan 8 Task 1); no home screen has been looked at | **pending simulator** |
| VoiceOver: Queue row / Collection cell / bookmark row / mini-player title read as one element each | wired in Plan 8 Task 4 — `.accessibilityElement(children: .combine)` on the Queue row's meta line, a combined label on the Collection cell, `BookmarkRow`'s own combined label, the mini-player title wrapped in an activatable `Button`; `scripts/build-app.sh` — `** BUILD SUCCEEDED **`; never run under VoiceOver | **pending hardware** |

## The iPhone 17 Pro run (for Harsh)

**This visit is optional now.** Core ML is the baseline runtime on every phone (Plan 0 Task 8, and
Plan 6 shipped it), so nothing in the app waits on these numbers any more. The reason to do the run
is a comparison: if MLX on an A14+ phone beats Core ML's RTF 0.181 by enough to change an offered
rate or battery life, the routing already has a place for it — `KokoroVoiceRouting` holds one route
per engine identity, and both engines are linked into `T2SReaderKokoro` today. If it does not, the
MLX route simply stays wired, gated and unmeasured.

Two halves. The **spike harness** produces the Plan 0 numbers; the **app** proves the MLX route
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
scripts/fetch-kokoro-coreml.sh --app   # the Core ML files: the app's default voice needs them
scripts/fetch-kokoro-model.sh          # the MLX weights, or the build bundles no MLX voices
open App/T2SReader.xcodeproj           # generated by scripts/build-app.sh or scripts/build-device.sh
```

- Scheme **`T2SReaderKokoro`** (not `T2SReader`). It is device-only by design; the simulator cannot
  link MLX.
- Signing & Capabilities → your own team, on **both** `T2SReaderKokoro` and `T2SReaderShare`. The
  app group `group.com.t2s.reader` must stay on both or the app cannot open its library. A free
  personal team allows three apps on a device and an app with an extension counts twice.
- Edit Scheme → Run → Arguments → Environment Variables: `T2S_KOKORO_DEBUG_OVERRIDE` = `1`. That
  flag is the **MLX** route's alone. Without it `KokoroRuntimeDecision.current` is `nil`, the MLX
  route reports itself unavailable, and every document plays on the Core ML route instead — correct
  behaviour, just not what you came to test. (The `kokoro.debugOverride` user default does the same
  thing.) The override is compiled out of Release builds; with it on, the Preferences footer gains a
  second line, "MLX route: development override active.", and the picker gains a second set of 28
  voices whose rows end in " · MLX". With the override on, Kokoro also runs in Prepare and in
  background play-ahead — that is the §7.2/§7.7 experiment, not an enforced policy yet: the
  decision's `backgroundInferencePermitted` and `idleInferencePermitted` flags are recorded but read
  nowhere.
- Build and run on the phone from Xcode. `scripts/build-device.sh` builds the same target unsigned
  from the command line — useful for a compile check, useless for installing.
- In the app: Preferences → Voice → the **Kokoro (beta)** section. Read the footer first: the first
  line is the Core ML route, the second the MLX one. Pick a voice whose row ends in " · MLX", then
  play a book and let it run.
- What to report back: does the second footer line appear; does the first sentence play; how long
  the first utterance takes versus later ones (MLX compiles Metal kernels during the first
  synthesis); whether the read-along highlight tracks at word level (Plan 6 opened the §7.4 timing
  gate for both runtimes); and anything in the log under subsystem `com.t2s.reader`.

If a `devicectl` install is used instead of Xcode, build Release with `ENABLE_DEBUG_DYLIB=NO` —
Xcode's debug-dylib layout leaves the package frameworks in DerivedData and the installed app
aborts at launch with `Library not loaded: @rpath/KokoroSwift.framework`. The app target itself
does embed `KokoroSwift.framework` correctly, so the spike harness's manual copy-and-re-sign step
is **not** needed here.

## Resume here (2026-09-04)

Plan 6 (`docs/superpowers/plans/2026-09-04-plan-6-coreml-kokoro-engine.md`, the Core ML Kokoro
engine) is **finished on branch `plan-6-coreml-engine`** — Tasks 1–6, each committed and reviewed —
checked out in the git worktree `.worktrees/plan-7-coreml-engine` (the directory kept the name it was
created with, before the plans were renumbered; `git worktree list` tells). It is **not merged**: the
one thing left is the first listen on the owner's iPhone 11 Pro, written out below. Do that, fix
whatever it turns up, then merge to `dev`.

What landed:

- **Task 1** — `Packages/KokoroPipeline`, a vendored copy of `mattmireles/kokoro-coreml` @
  `66d8cf51` (Apache-2.0; the upstream repository keeps its `Package.swift` in a `swift/`
  subdirectory, which SwiftPM cannot consume by URL), and `scripts/fetch-kokoro-coreml.sh --app`,
  which stages the eight Core ML stages, the 28 English voices, the vocab and the hn-NSF weights
  into the git-ignored `App/Resources/KokoroCoreML` — 54 files, 347 MB, every one sha256-verified.
- **Task 2** — `KokoroCoreMLResources` (the file contract), `KokoroCoreMLDecision` (the A13
  measurement: RTF 0.181, so every rate up to 4x is offered, and a 119 MB footprint) and
  `KokoroTokenizer`.
- **Task 3** — `KokoroCoreMLEngine`: an actor, every stage on the CPU, identity
  `kokoro-coreml-2e878c6a-misaki1.0.6`. It produces real per-word timings folded from the
  pipeline's duration frames, which is what opened the spec §7.4 gate in `KokoroTokenTimingMapper`
  for both runtimes, and it chunks an utterance longer than the pipeline's 15 s bucket into pieces
  of at most 176 tokens, cut at word boundaries.
- **Task 4** — `RoutedEngine` holds several Kokoro engines keyed by identity; `KokoroVoiceRouting`
  holds one route per identity plus a default-voice rule ("default" → Kokoro Heart on the Core ML
  route while that route is available, leaving the stored document voice untouched);
  `KokoroVoiceCatalog` lists every linked runtime, MLX rows ending in " · MLX".
- **Task 5** — the app. `T2SReaderKokoro` bundles `Resources/KokoroCoreML` (Xcode compiles the
  `.mlpackage`s into `.mlmodelc`; the `.app` is 433 MB), `GatedKokoroCoreMLEngine` and a
  first-launch warm-up shown in the Preferences footer, the MLX route kept beside it with its
  voices listed only once its probe answers `.available` (A14+, weights staged, development
  override on), the "Default voice" row resolving through the routing, and both build scripts plus
  CI's "Generate app project" step creating the two git-ignored resource directories before
  `xcodegen` — it refuses a missing source path.
- **Task 6** — this documentation.

The ledger with every ruling is
`.superpowers/sdd/2026-09-04-plan-6-coreml-kokoro-engine/progress.md` inside that worktree, with a
report per task beside it.

Two things Task 3 learned that will bite anyone who runs the package tests. The engine's
*development* path (raw `.mlpackage` staging, which `scripts/test-kokoro.sh` uses) compiles the
eight stages into `$TMPDIR` on every engine instance and never removes them, so each model-backed
engine test leaks about 350 MB — 4.7 GB was found and deleted here in one night, and
`rm -rf "$TMPDIR"/kokoro_*.mlmodelc` is the reclaim. The app bundle is precompiled, so it compiles
nothing and leaks nothing. And `preload()` is `async` with a shared compile, so a render cancelled
during a cold load waits the compile out rather than returning promptly.

### The first listen, on the owner's iPhone 11 Pro

Prerequisite, once per machine: `scripts/fetch-kokoro-coreml.sh --app` must have staged
`App/Resources/KokoroCoreML` (it has, on this Mac — 347 MB). `scripts/fetch-kokoro-model.sh` (the
MLX weights) is **not** needed and is deliberately absent here.

Phone on USB, **unlocked** (`devicectl` refuses a launch on a locked device), and trusted.

**1. Find the two device identifiers.**

```bash
xcrun devicectl list devices        # CoreDevice UUID — what devicectl wants
xcrun xctrace list devices          # UDID (00008030-…) — what xcodebuild -destination id= wants
```

**2. Signed Release build.**

```bash
cd ~/Developer/t2s_reader/.worktrees/plan-7-coreml-engine/App
mkdir -p Resources/Kokoro Resources/KokoroCoreML
xcodegen generate --quiet
xcodebuild build -scheme T2SReaderKokoro -destination 'generic/platform=iOS' \
  -configuration Release -derivedDataPath ../.build/DerivedData-App \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=V69PL7U8EX ENABLE_DEBUG_DYLIB=NO
```

`ENABLE_DEBUG_DYLIB=NO` is not optional for a `devicectl` install: Xcode's debug-dylib layout leaves
the package frameworks in DerivedData and the installed app aborts at launch with `Library not
loaded: @rpath/…`.

If automatic signing has never run for this team from the shell it will fail, because the profile
has to exist first. Two ways out: add `-allowProvisioningUpdates` (which works only if Xcode is
already signed in), or do the whole thing in the GUI instead —

> `open App/T2SReader.xcodeproj` → scheme **`T2SReaderKokoro`** (not `T2SReader`) → Signing &
> Capabilities → the team on **both** `T2SReaderKokoro` **and** `T2SReaderShare`, keeping the
> `group.com.t2s.reader` app group on both → build configuration Release (Edit Scheme → Run → Info)
> → Run on the phone. A free personal team allows three apps on a device and an app with an
> extension counts twice; `MIFreeProfileValidatedAppTracker … ApplicationVerificationFailed` means
> remove one.
>
> Do **not** set `T2S_KOKORO_DEBUG_OVERRIDE` this time. That flag is the MLX route's development
> escape hatch; the Core ML route needs nothing from it, and on the 11 Pro it would change nothing
> anyway — the A13 fails the GPU-family gate whatever the override says.

**3. Install and launch from the command line.**

```bash
WT=~/Developer/t2s_reader/.worktrees/plan-7-coreml-engine
APP=$WT/.build/DerivedData-App/Build/Products/Release-iphoneos/T2SReaderKokoro.app
xcrun devicectl device install app --device <CoreDevice-UUID> "$APP"
xcrun devicectl device process launch --device <CoreDevice-UUID> --terminate-existing com.t2s.reader
```

**4. Watch the log** in a second terminal, started *before* the launch.

```bash
log stream --predicate 'subsystem == "com.t2s.reader"' --style compact
```

Lines to look for, in order:

- `Kokoro Core ML route available (coreml-cpu, RTF 0.181)` — the bundle's files were found.
- `Kokoro MLX unavailable: …` — expected on the 11 Pro (the A13 fails the GPU-family gate, and no
  MLX weights are staged in this build anyway). It is silent in the UI by design.
- **`Kokoro Core ML warm-up finished in <N> s`** — the number this whole run is for. The A13 spike
  measured **206 s** to build the compute plans on a *first* launch; later launches should be
  seconds. `Kokoro Core ML warm-up failed, retrying: …` means the first attempt threw and a second
  starts two seconds later; `… failed, route closed: …` means both did and the phone will speak
  this book with the system voice. Capture either message.
- `voice route resolved: default → kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart` when a
  document loads.

**5. The checklist.**

1. **First launch, before anything else:** Preferences → Voice → the **Kokoro (beta)** footer should
   read *"Preparing the Kokoro voice (one-time, up to a few minutes on the first launch)…"*. Note
   how long it stays there — expect around 206 s on this phone the first time, seconds afterwards —
   then it must flip to *"Runs on this device."*. There should be **no** second "MLX route:" line.
2. **Stop during the warm-up** — the first launch is the only chance, so do it while that footer
   still says "Preparing…". Open any book, press play, wait a few seconds, then press stop. The
   render does *not* cancel promptly: the stage load is shared, and a waiter cancelled during a cold
   load sits out the whole compile before it comes back. So what is being checked is that the app
   survives it — the transport goes back to stopped, nothing spins forever, and playback works
   normally once the warm-up line lands in the log. Note whether an error banner appears (it may;
   what matters is that the app is not wedged), and report a stuck transport or a spinner that
   never clears.
3. Preferences → the **Default voice** row's grey subtitle should read **"Heart · en-US"**, not
   "System default", once the page has appeared.
4. Preferences → Voice: the Kokoro section lists **28** voices, each named like "Heart · en-US" —
   **one** set, with no " · MLX" rows.
5. Import a **fresh** EPUB (share sheet, or the `t2s:` URL). Fresh matters: a document imported
   before this build already has a stored `voiceID`. Press play without choosing a voice —
   **Kokoro Heart should speak**, not the system voice. Time the wait from tap to first audio.
6. **Read-along:** the highlight should follow **individual words**, not whole sentences.
   Sentence-level highlighting means the word timings did not arrive, and is worth reporting.
7. **A long sentence, listened to at the seam.** Find or paste one of about **60 words or more**
   (Dickens and Melville oblige; so does a pasted paragraph with the full stops taken out). The
   duration model tops out at 256 tokens, so the engine cuts anything longer into pieces of ≤ 176
   phoneme ids, synthesizes them separately and concatenates the audio — about 13 seconds a piece.
   Listen at the joins for a click, a swallowed or doubled word, or a gap, and watch that the
   highlight keeps tracking across them. A prosody dip at the seam is expected and fine; a missing
   word is not.
8. **Speed:** the picker should offer **2x and 4x** (`maxSustainableRate` is 4.0, from RTF 0.181).
   Play at 4x for a minute and listen for dropouts.
9. **Lock screen:** lock the phone mid-playback. Play/pause, skip back, skip forward, the title and
   the artwork should all work from the Lock Screen and Control Center.
10. Report back: the warm-up seconds, whether stopping during the warm-up left the app usable, the
    tap-to-first-audio latency at 1x, whether word highlighting tracks, how the seam in a long
    sentence sounds, whether 4x sustains, whether the Lock Screen controls work, and anything in the
    `com.t2s.reader` log that is not in the list above.

**Plan 8 is also complete**, on branch `plan-8-bookmarks-icon-voiceover`, stacked on
`plan-6-coreml-engine` in this same worktree — merge it after Plan 6. It adds a bookmark list
(add from the Player or the Reader's overflow, browse it from the Book sheet or from either
overflow's **Bookmarks** item, tap to jump, long-press to delete anywhere and swipe too in the
Bookmarks list), a drawn app icon on
both app targets, and VoiceOver fixes that fold the Queue row, the Collection cell, a bookmark
row and the mini-player title into one element each instead of several separate stops. Two
deferred minors worth knowing: the "·" separators folded into the Queue row's combined label may
be read aloud as "middle dot", and `scripts/make-app-icon.swift`'s default output path is
relative to the repo root, so running it from elsewhere writes a nested tree instead of
overwriting the catalog. The final whole-branch review's two fixes have landed — an opaque app
icon and a bookmark snippet clamp that survives fallback resolution — and the deferred minors it
left are recorded in that review's ledger.

## What comes after

The product owner decided on 2026-09-03 that Kokoro is the app's main engine (the system voice is
a placeholder), and Plan 6 made that true on the Core ML route: measured constants, real word
timings, and Kokoro Heart as the default voice on the phone build.

**Where that runtime decision came from.** Plan 0 Task 8, 2026-09-04,
`spikes/findings/2026-09-04-pre-a14-runtime.md`: `mattmireles/kokoro-coreml`'s `KokoroPipeline`
(Apache-2.0) with **every stage on the CPU** gives median RTF 0.18 flat out and 0.16 over 20 minutes
at 4x on the A13, a flat 119 MB footprint, and word-onset timing within 55 ms — so every rate up to
4x is offered and the rate-cap / prepare-the-whole-book idea is not needed on this phone (it stays
the design for any slower device). The GPU-assisted policy is slower there (0.37) and needs 1.2 GB;
MLX on the CPU is dead (RTF 15). The desk research behind the choice is
`spikes/findings/2026-09-03-pre-a14-runtime-options.md`; the harness arm and its fetch script are
`spikes/SpikeHarness/SpikeHarness/CoreMLBench.swift` and `scripts/fetch-kokoro-coreml.sh` (see
`spikes/README.md`, "Core ML arm", for the stale-manifest fix and the launch switches). That task's
word-end fold follow-up was fixed in Plan 6 Task 3: the trailing pause is charged to the
punctuation, not to the word.

**One correction, because it shaped Plan 6 and was wrong.** The owner's direction as recorded here
on 2026-09-04 said that Core ML also runs in the simulator, so the engine belonged in the everyday
`T2SReader` target and would make Kokoro testable on the Mac. It cannot: MisakiSwift — the G2P both
runtimes need — links mlx-swift, which cannot link against the iOS simulator SDK. The Core ML engine
therefore lives in the device-only `T2SReaderKokoro` target and in the macOS test bundle, and
`T2SReader` stays the simulator and CI build, with the system voice and no engine linked.

What remains, in order:

1. **The first listen on the iPhone 11 Pro, then merge Plan 6.** The recipe is under "Resume here"
   above. Nothing on that branch has spoken on a phone, and every "pending the owner's listen" row
   in the matrix turns on it.
2. **The unplugged 20-minute run at 4x on the 11 Pro** — the number Plan 0 Task 8 left open.
   Thermal state 2 was reached on charge at 4x with no speed collapse; the unplugged thermal curve
   and the battery drain are unmeasured. The protocol is `spikes/README.md`, "Core ML arm", and the
   finding to extend is `spikes/findings/2026-09-04-pre-a14-runtime.md`.
3. **Plan 0 measurements on the iPhone 17 Pro (Harsh) — optional now.** Core ML is the baseline on
   every phone, so nothing waits on these; do them when a comparison is worth having (see "The
   iPhone 17 Pro run" above for when it is). The plan is
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
4. **Wire the 17 Pro numbers into the code, if that visit happens.** The MLX engine, probe, route,
   catalog, fallback and UI all exist (Plan 5 Task 5, kept alive by Plan 6); only the measured
   constants are missing. When the findings files land, in this order:
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
   - The `KokoroTokenTimingMapper` work is **done**: Plan 6 Task 3 opened the §7.4 gate against the
     A13 measurement, for both runtimes, so the MLX route already returns real word timings. Two
     caveats the Task 5b review recorded still stand and would be settled by a 17 Pro fixture rather
     than by reasoning: (a) `candidateTimings` does not advance `searchFrom` past a skipped token,
     so adjacent repeated words can bind to the wrong range; (b) `MToken.tokenRange` may be a better
     alignment source than searching the text at all.
   - Making a Kokoro voice the default is **done** too, on the Core ML route (Plan 6 Task 4). The
     product cost it carries is unchanged and applies to any later route change: the render key
     carries the engine identity, so a document that switches route re-derives its audio
     (spec §3.7.3).
5. **The hardware matrix above.** Every row marked *pending hardware* — the Lock Screen and route
   changes, the Share Extension payloads, Prepare's power and thermal stops, `BGProcessingTask`,
   and the cloud error paths — plus Plan 4b Task 9's remaining EPUB/PDF fixture and UI test. A
   failing row is a fix round, not a footnote.
6. **Plan 7** (renumbered 2026-09-04; Plan 6 is the Core ML engine) is unchanged: CloudKit sync behind `SyncProvider`, Live Activity, App Intents, and
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
6. **Kokoro's gate: the Core ML route is open, the MLX route is not.** Core ML runs on measured
   constants — `KokoroCoreMLDecision.current` carries the A13's RTF 0.181 and 119 MB, every rate up
   to 4x is offered, `KokoroTokenTimingMapper` returns real word timings, and Kokoro Heart is the
   default voice on the phone build (Plan 6). The MLX route still has **no** constants:
   `KokoroRuntimeDecision.current` is `nil` and the engine refuses to be selected while it is, so
   its voices appear only behind the `DEBUG` override. The 17 Pro numbers (§7.2–§7.5, §7.7) decide
   its rate threshold, memory limits and background policy. The iPhone 11 Pro cannot run that route
   at all (Plan 0 Task 8), which is why the Core ML one exists.
7. **A Kokoro engine failure after the probe has passed leaves the book playing silence.** The
   availability probe runs once, at configuration time (adjustment 3 scopes the fallback there), so
   a failure inside `KokoroEngine.load()` or `generateAudio` — a corrupted weight file, an MLX
   allocation failure, jetsam pressure — throws per utterance from then on. The coordinator does
   what spec §6 asks: it surfaces the message as `lastRenderError` and fills 200 ms of silence, so
   the book does not halt. But there is no re-route after the probe, so it plays silently with an
   error showing until the reader changes the voice by hand. Follow-up: on the first
   `KokoroEngineError` out of `GatedKokoroEngine`, flip `KokoroAvailabilityModel` to unavailable
   (a new reason, e.g. `.engineFailed`) so the next load falls back to the system voice and the
   Preferences footer says why. **Plan 6 closes this on the Core ML route.**
   `GatedKokoroCoreMLEngine` no longer remembers a failed load, so a transient failure costs one
   utterance instead of the session; and the launch warm-up now decides the *route*, not just the
   footer — it tries `preload()` twice, two seconds apart, and a second failure closes the Core ML
   route for the rest of the launch, so every document opened from then on falls back for its whole
   length (spec §6) instead of failing utterance by utterance. The footer then reads "Not available
   on this device: The Kokoro voice could not be prepared. …" — a constant, because
   `error.localizedDescription` for a plain Swift error reads "The operation couldn't be
   completed."; the real error goes to the log (`Kokoro Core ML warm-up failed, route closed: …`).
   What is left: a document already routed to Kokoro when the route closes keeps failing per
   utterance until it is reloaded, a cancelled warm-up neither retries nor closes anything, and a
   route closed by two unlucky transient failures stays closed until the app is relaunched.
   Whether the route falls back to the *system* voice or to another Kokoro voice is the resolver's
   business, not this one's: an unavailable `kokoro:` ID resolves to the app's default voice
   (Kokoro Heart on Core ML where that route is open), and only to the system voice when no Kokoro
   route is left — which is how a model-revision bump re-routes old documents to the new default.
   **One engine failure is by design and worth recognising in the log:** a piece of an utterance
   whose predicted speech still overruns the 15-second bucket throws
   `KokoroCoreMLError.audioTruncated(predictedSeconds:bucketSeconds:)` rather than return speech
   clipped to fit, so that sentence is dropped and filled with 200 ms of silence like any other
   engine failure, and the reader sees "The on-device voice could not fit this passage into one
   breath." The chunker aims at about 13 seconds a piece, so it should be rare — but it means
   "a sentence went silent" is diagnosable rather than mysterious: look for `audioTruncated` and
   its two second-counts in the log.
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
   `Packages/T2SReadium/.build` all regenerate from the scripts that use them. Plan 6 adds two
   appetites. `App/Resources/KokoroCoreML` is 347 MB, a device build now leaves about 3.3 GB in
   `.build/DerivedData-App` and produces a 433 MB `.app`. And the Core ML engine's *development*
   path compiles the eight `.mlpackage` stages into `$TMPDIR` on every engine instance and never
   removes them, so each model-backed test leaks about 350 MB — 4.7 GB accumulated here in one
   night. `scripts/test-kokoro.sh` now sweeps `"$TMPDIR"/kokoro_*.mlmodelc` before it starts, so the
   leak is one run's worth rather than every run's; the same command reclaims it by hand, macOS
   clears them on reboot, and the app bundle is precompiled and leaks nothing on the phone.
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
11. **The phone app is `T2SReaderKokoro`, not `T2SReader`.** The two-target split is no longer only
    about MLX. `T2SReader` is the simulator, CI and everyday build: it links no engine and speaks
    with the system voice. `T2SReaderKokoro` is device-only, links both runtimes, bundles the
    347 MB of Core ML files, and is the only target where Kokoro is the default voice. Core ML on
    its own would not have needed a device-only target, but MisakiSwift — the G2P it uses — links
    mlx-swift, which cannot link against the simulator SDK. So anything a reader is meant to *hear*
    has to be built and installed from `T2SReaderKokoro`; a simulator screenshot shows the system
    voice by design, not by accident.
12. **The MLX voices appear a few seconds into a launch, not at launch.** `KokoroVoiceCatalog` asks
    a closure for the linked runtimes on every `voices()` call, and that closure reads a flag the
    MLX probe sets when it answers; `VoiceListPage` re-evaluates its body because it also reads
    `kokoroStatus.mlxLine`, which is written immediately after the flag, and the re-evaluation
    re-asks `voices()`. So the second set of 28 rows (" · MLX") arrives on that redraw. `PreferencesPage`
    does not observe `mlxLine`, so its "Default voice" subtitle picks up the fuller catalog on its
    own next redraw — cosmetic, and it only ever shows a Core ML voice anyway. All of this is
    reachable only on an A14+ phone with the MLX weights staged and the override on.

Other retained review items:
- Same bug class as the artwork crash, unproven: `MainActor.assumeIsolated` inside the
  `MPRemoteCommand` handlers in `NowPlayingController.start()` and in the `deinit`s of
  `NowPlayingController` and `AudioPlayer`. They hold as long as MediaPlayer delivers commands on
  the main thread and those objects are only ever released on it; the Lock Screen / AirPods pass on
  hardware is where they would show.
- ~~No app icon / asset catalog yet — blocking for TestFlight, fine for development.~~
  **Resolved**: the icon exists (`scripts/make-app-icon.swift`, opaque RGB — no alpha channel, so
  App Store Connect's ITMS-90717 icon-alpha check does not reject it) and draws a deterministic
  CoreGraphics icon (accent (#FF7A1A) ground, three rounded white bars, a play triangle) into
  `App/T2SReader/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`; both app targets pick it
  up through `ASSETCATALOG_COMPILER_APPICON_NAME` in the shared `targetTemplates` entry.
  Regenerate the PNG after editing the script with `swift scripts/make-app-icon.swift`. App Store
  upload validation itself has not yet run — pending an upload.
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
