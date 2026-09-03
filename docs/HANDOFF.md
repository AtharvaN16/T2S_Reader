# t2s_reader — hand-off and next steps

_Last updated 2026-09-03, evening (playback crash fixed; Plan 0 spikes §7.1 and §7.3/§7.5 recorded; Kokoro direction decided). Written for whoever picks up the coding next._

## What this is

An iOS app that turns EPUBs, web articles, and text PDFs into read-along audiobooks
synthesized on the phone. The design spec is the source of truth:
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](superpowers/specs/2026-09-01-t2s-reader-design.md)
(rev 7). Work is organised as numbered plans under
[docs/superpowers/plans/](superpowers/plans/), each a list of tasks with the exact code, tests,
and commit message per task. The roadmap is
[2026-09-02-t2s-reader-roadmap.md](superpowers/plans/2026-09-02-t2s-reader-roadmap.md).

## Branches

| Branch | State | Notes |
|---|---|---|
| `dev` | integration branch, everything below is merged here | Plans 1–4a, Plan 4b Tasks 1–8, Plan 5 Tasks 1–4, the playback crash fix, and the Plan 0 spike findings so far are merged (`499d3fa`). Root package: 293 tests in 68 suites; the app builds, launches, imports an EPUB, and plays it on the simulator and on an iPhone 11 Pro. |
| `main` | stale: only the initial spec commit | Not used for integration yet; fast-forward it to `dev` when you want a release point. |

Plan branches are short-lived: each plan runs on its own branch off `dev` (locally in a git
worktree under `.worktrees/`, git-ignored) and is merged and deleted when its final review is clean.

## Toolchain

- Xcode 26.6 (Swift 6.2), macOS 15+. CI uses that single pinned toolchain, restores both SPM and Xcode package caches, and retries transient package resolution. `brew install xcodegen`. An iPhone simulator installed.
- `swift test` — the root package on macOS (everything except Readium).
- `scripts/test-readium.sh` — the iOS-only Readium package on the simulator (`SIMULATOR_ID=<udid>` to pick one).
- `scripts/build-app.sh` — regenerates `App/T2SReader.xcodeproj` from `App/project.yml` and builds the app for the simulator. Then `open App/T2SReader.xcodeproj` to run it.
- `scripts/check-licenses.sh` — fails on any copyleft dependency (CI runs it).

Never commit generated files (`*.xcodeproj`, `App/T2SReader/Info.plist`, `.build/`); one `.gitignore` at the root.

## What exists (all on `dev`)

- **T2SCore** — text pipeline: normalizer with span mapping, sentence segmenter, two-phase timeline (estimated → actual durations), per-chapter codec, `Position` resolution, highlight projection, render policy tiers, render scheduler, audio cache with LRU. Plan 1 + Plan 2.
- **T2SAudio** — `AudioPlayer` on `AVAudioEngine` with pitch-corrected rate, `PlaybackCoordinator` (owns the playhead), `AACCodec`, and `SystemSpeechEngine` (AVSpeechSynthesizer; the engine until Kokoro lands). Plan 2 + Plan 4a.
- **T2SStore** — SwiftData store (`LibraryStore`): documents, per-chapter timeline blobs, queue order, resume positions as flattened columns, bookmarks, pronunciation dictionary; versioned schema; `PlayheadStore` conformance. Plan 3.
- **T2SLibrary** — `Library` facade (import file / article, delete, re-derive stale timelines, evict audio), `PDFDocumentReader` (PDFKit), stored-only ZIP writer, `ArticleEPUBWriter`, container layout `LibraryPaths`. Plan 3.
- **Packages/T2SReadium** (iOS only) — `ReadiumDocumentReader` (EPUB → chapters with stable `Position`s) and `LocatorMapping` (`Position` ↔ Readium `Locator`, word-highlight quotes). Plan 3.
- **T2SApp** (root package target, testable on macOS) — the app's models: `LibraryModel`, `PlayerModel`, `ScrubberModel`, `ImportModel`, `DurationFormatter`, `AppPaths`, `DeviceStateMapping`. Plan 4a.
- **App/** — the SwiftUI app `T2SReader`: design tokens and type roles (Inter, bundled), composition root, three-page pager with mini-player, Queue page, Collection page + book sheet, player sheet with the tick scrubber, Add sheet (paste a link → WKWebView + Readability.js extraction preview, open a file, paste text), audio session + device monitor. Plan 4a.

## Where things are right now

The integration branch is at `499d3fa` (spike findings on top of the PR #14/#15 merges). The completed work is:

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

The app has been built and launched on the simulator. The latest full root-package test result is
293 tests in 68 suites (on `fix/nowplaying-artwork-isolation`, see below); PR #13 reported 291 in
66 before it. CI is the authority for the iOS-only Readium coverage.

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

## What comes after

The product owner decided on 2026-09-03 that Kokoro is the app's main engine (the system voice is
a placeholder), so the order is now driven by opening the Plan 5 Task 5 gate.

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
   and a `RESOLVED` line under each spec §7 subsection.
2. **Plan 5 Task 5 — Kokoro for A14+ devices** (plan section in
   [2026-09-03-plan-5-engine-share-nowplaying.md](superpowers/plans/2026-09-03-plan-5-engine-share-nowplaying.md)).
   The parts that do not need the 17 Pro numbers can start now: the package pins (kokoro-ios
   1.0.11, mlx-swift 0.30.2, MisakiSwift 1.0.6), model/voice acquisition with SHA-256 checks,
   `KokoroEngine` with the `supportsFamily(.apple7)` probe and the whole-document fallback to
   `system:<voice>`, the route and voice catalog, and the `NumberWords` spacing fix. The
   `KokoroRuntimeDecision` constants (measured RTF, the derived rate threshold, memory limits) and
   the timing-mapper fixture must come from the 17 Pro CSV; do not guess them. **The design was
   approved on 2026-09-03 and is written into the plan as "Task 5 adjustments"**: a new
   `Packages/T2SKokoro` (MLX needs its Metal library, which `swift test` and the simulator cannot
   provide, so it is tested with `xcodebuild` on macOS, where MLX runs), `KokoroEngine` as an
   actor, `KokoroAvailability` gating on `supportsFamily(.apple7)` + checksums + a complete
   `KokoroRuntimeDecision`, a `kokoro:` route in `RoutedEngine`, "Kokoro (beta)" voices, timings
   held at `[]` until the 17 Pro fixture, and a `DEBUG` override for development. Start it on
   branch `plan-5-task-5-kokoro` with the executing-plans workflow; the order of work is in the
   plan.
3. **Plan 0 Task 8 — a runtime for pre-A14 phones** (the owner's own iPhone 11 Pro): a one-day
   timeboxed spike on an ONNX Runtime / CoreML Kokoro (sherpa-onnx first), same pass bar as §7.3.
4. **Plan 4b Task 9 leftovers and hardware checks.** The read-along has passed on the simulator and
   on the 11 Pro; the EPUB/PDF fixture and the UI test are still not written. Hardware
   verification of the Share Extension (URL, text, EPUB, PDF), call interruption and AirPods route
   changes, Lock Screen / Control Center, and `BGProcessingTask` scheduling remain open.
5. **Plan 5 Task 6 and Plan 6** follow. Plan 6 is unchanged: CloudKit sync behind `SyncProvider`,
   Live Activity, App Intents, and Spotlight.

## Known issues and parked items

1. **Plan 4b Task 9 is open:** the EPUB read-along has now passed once on the simulator (see
   above), but the pass on hardware, the EPUB/PDF fixture, and the UI test are still not done.
   A usable fixture already sits in Readium's checkout
   (`Tests/Publications/Publications/childrens-literature.epub` under `swift-toolkit`).
2. **`scripts/build-app.sh` produces an app that cannot open its library.** It builds with
   `CODE_SIGNING_ALLOWED=NO`, so since PR #15 moved the library into the app group the simulator
   app has no `application-groups` entitlement, `containerURL(forSecurityApplicationGroupIdentifier:)`
   returns nil, and the app shows "The library could not be opened." Build with ad-hoc signing
   instead (`CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-`) or run from
   Xcode until the script is updated.
3. **Physical-device validation remains open:** audio through phone-call interruption and AirPods
   route changes; Lock Screen and Control Center controls; and debugger-forced
   `mediaServicesWereReset` recovery. PR #9 verified the software seams, not these hardware paths.
4. **Background processing remains device-only:** PR #12 verified the runner and visible state on a
   simulator, but the simulator rejects the opportunistic request. Validate `BGProcessingTask`
   scheduling and simulated launch while the device is on charge.
5. **Share Extension remains unverified on hardware:** Task 2 merged in PR #15. Verify the share
   sheet on a physical device for URL, text, EPUB, and PDF input and the hand-off into the host.
6. **Kokoro's gate is half open.** §7.1 is resolved and the MLX route is known to need A14+; the
   17 Pro numbers (§7.2–§7.5, §7.7) still decide the rate threshold, memory limits, background
   policy, and whether word timings can drive the highlight. Plan 5 Task 5 may build the engine,
   probe, route, and fallback now but must not ship guessed constants. The iPhone 11 Pro cannot run
   this route at all (Plan 0 Task 8).

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
- Run `swift test` and `scripts/build-app.sh` before every commit that touches the app; `scripts/test-readium.sh` when `Packages/T2SReadium` changes.
- Commit trailer used for current AI-written commits: `Co-Authored-By: Codex <noreply@openai.com>`.
