# t2s_reader — hand-off and next steps

_Last updated 2026-09-03 (after Plan 4b and Plan 5 Tasks 1 and 3 merged). Written for whoever picks up the coding next._

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
| `dev` | integration branch, everything below is merged here | Plans 1–4a, Plan 4b Tasks 1–8, and Plan 5 Tasks 1 and 3 are merged. The latest root-package verification was 291 tests in 66 suites (PR #13); the app builds and launches on the simulator. |
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

The integration branch is at merge commit `e878767` (PR #12). The completed work is:

- **Plan 4a** is complete.
- **Plan 4b Tasks 1–8** are merged: PR #2 (Reader models and preferences), PR #3 (pronunciation,
  storage, and voice-change models), PR #4 (Reader and appearance UI), and PR #7 (Preferences and
  voice-change UI). PR #10 is the Reader review-fix wave; PR #11 is the Preferences review-fix wave.
  They include safe destructive audio-change APIs, no-op unchanged voices, session-owned voice
  previews that stop on disappearance, robust Readium/PDF handling, and publication cleanup.
- **Documentation and CI**: PR #5 documented the Reader controls; PR #6 made CI deterministic on a
  single Xcode 26.6 toolchain and added SPM/Xcode package caches plus package-resolution retries.
- **Plan 5** is written in PR #8. Task 1 (Now Playing, remote controls, and media-services recovery)
  merged in PR #9. Task 3 (multi-document Prepare and `BGProcessingTask`) merged in PR #12. Task 4
  (BYO-key cloud engine) is currently open as [PR #13](https://github.com/AtharvaN16/T2S_Reader/pull/13).
  Task 2 (Share Extension) has no GitHub PR or remote branch yet; its planned branch name is
  `plan-5-task-2-share-extension`.

The app has been built and launched on the simulator. The latest full root-package test result is
291 tests in 66 suites (reported by PR #13); PR #12 independently passed 280 tests before it
merged. CI is the authority for the iOS-only Readium coverage.

## What comes after

1. **Finish Plan 4b Task 9 first.** It has not been done: run the manual read-along pass on real
   hardware, add an EPUB/PDF fixture, and add the planned UI test. Do not call Plan 4b complete
   until those three deliverables are recorded.
2. **Finish Plan 5 Tasks 2 and 4.** Task 2 (Share Extension) remains pending with no GitHub PR or
   remote branch at this hand-off. Review/merge Task 4 from PR #13 after its checks and review are
   clean; it adds the BYO-key HTTP route, Keychain storage, Cloud voices preferences, rate limiting,
   and render-key isolation between engines/voices.
3. **Plan 0 spikes (device work)** —
   [2026-09-02-plan-0-spikes.md](superpowers/plans/2026-09-02-plan-0-spikes.md): the harness under
   `spikes/SpikeHarness/` (xcodegen) with Kokoro via `kokoro-ios`. Spec §7.2 background compute,
   §7.7 `BGProcessingTask`, §7.3/§7.5 runtime and memory, §7.4 word-timing accuracy, §7.1 MisakiSwift
   coverage + the license audit. Findings go in `spikes/findings/`. Kokoro (Plan 5 Task 5) remains
   gated on accepted findings from every required spike.
4. **Plan 5 Task 6 and Plan 6** follow the remaining Plan 5 work. Plan 6 is unchanged: CloudKit
   sync behind `SyncProvider`, Live Activity, App Intents, and Spotlight.

## Known issues and parked items

1. **Plan 4b Task 9 is open:** no manual read-along pass on hardware, no EPUB/PDF fixture, and no
   UI test have been completed.
2. **Physical-device validation remains open:** audio through phone-call interruption and AirPods
   route changes; Lock Screen and Control Center controls; and debugger-forced
   `mediaServicesWereReset` recovery. PR #9 verified the software seams, not these hardware paths.
3. **Background processing remains device-only:** PR #12 verified the runner and visible state on a
   simulator, but the simulator rejects the opportunistic request. Validate `BGProcessingTask`
   scheduling and simulated launch while the device is on charge.
4. **Share Extension remains unverified:** Task 2 has not opened a PR. Once implemented, verify the
   share sheet on a physical device for URL, text, EPUB, and PDF input and the hand-off into the host.
5. **Kokoro is deliberately blocked** until the Plan 0 device spikes establish a viable runtime,
   timing, memory, G2P, background-compute, and license result.

Other retained review items:
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
