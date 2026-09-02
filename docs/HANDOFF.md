# t2s_reader — hand-off and next steps

_Last updated 2026-09-02. Written for whoever picks up the coding next._

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
| `dev` | integration branch, everything below is merged here | Plans 1, 2, 3 done. 206 root tests + 12 simulator tests green. Plan 4a and 4b documents committed. |
| `plan-4a-app-shell` | **in progress**, 17 commits ahead of `dev` | The iPhone app. Tasks 1–10 of 12 done; see below. Pushed to origin. |
| `main` | stale: only the initial spec commit | Not used for integration yet; fast-forward it to `dev` when you want a release point. |

Locally the Plan 4a branch was developed in a git worktree (`.worktrees/plan-4a`, git-ignored);
on a fresh clone just check the branch out normally.

## Toolchain

- Xcode 26.x (Swift 6.2), macOS 15+. `brew install xcodegen`. An iPhone simulator installed.
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
- **App/** — the SwiftUI app `T2SReader`: design tokens and type roles (Inter, bundled), composition root, three-page pager with mini-player, Queue page, Collection page + book sheet, player sheet with the tick scrubber. Plan 4a (on the branch).

## Where things are right now: Plan 4a

Plan file: [2026-09-02-plan-4a-app-shell.md](superpowers/plans/2026-09-02-plan-4a-app-shell.md).
Each task there carries its full code; execution has been task by task with a review after each.

| Task | Status |
|---|---|
| 1 App project, fonts, `T2SApp` target, build script, CI | done |
| 2 `SystemSpeechEngine` | done |
| 3 Formatters, container paths, device-state mapping | done |
| 4 `LibraryModel` + per-document progress | done |
| 5 `PlayerModel` + `ScrubberModel` | done |
| 6 Design system, composition root, root pager, mini-player | done |
| 7 Queue page | done |
| 8 Collection page + book sheet | done |
| 9 Player sheet, tick scrubber, chapter list, bookmarks | done |
| 10 `ImportModel` + extraction contract | done, **review in progress** |
| 11 Add sheet, link/text pages, file import, WKWebView + Readability extractor | **next** |
| 12 Audio session, device monitor, background persistence, docs | after 11 |

After Task 12: a whole-branch review, a fix wave, then merge `plan-4a-app-shell` into `dev` and push.

**Important honesty note:** the app has only been built for the simulator so far. Nobody has yet
run it and imported a document through the UI; Task 11's last step is the first manual check
(import a link → the player sheet opens and the system voice speaks). Expect the usual first-run
surprises there.

## What comes after

1. **Plan 4b** — Reader page (Readium navigator with the active word decorated, auto-scroll,
   tap-to-seek), speed picker, sleep timer, autoplay-next, Preferences (voices, playback, reading
   appearance, pronunciation dictionary, storage manager), per-document voice change.
   Written, not started: [2026-09-02-plan-4b-reader-controls.md](superpowers/plans/2026-09-02-plan-4b-reader-controls.md).
   Start it on a branch off `dev` after Plan 4a lands.
2. **Plan 0 spikes (device work — this was always meant for you)** —
   [2026-09-02-plan-0-spikes.md](superpowers/plans/2026-09-02-plan-0-spikes.md): the harness under
   `spikes/SpikeHarness/` (xcodegen) with Kokoro via `kokoro-ios`. Spec §7.2 background compute,
   §7.7 `BGProcessingTask`, §7.3/§7.5 runtime and memory, §7.4 word-timing accuracy, §7.1 MisakiSwift
   coverage + the license audit. Findings go in `spikes/findings/`. Plan 5 depends on these results.
3. **Plan 5** (not written yet) — Kokoro engine replacing `SystemSpeechEngine`, Share Extension
   (reuses `ArticleExtractor` + `ImportModel`), Now Playing / remote commands, multi-document
   Prepare runner with `BGProcessingTask`, BYO-key HTTP engine.
4. **Plan 6** (not written yet) — CloudKit sync behind `SyncProvider`, Live Activity, App Intents, Spotlight.

## Known issues and parked items

Flaky tests (timing under parallel load; pass alone):
- `PlaybackCoordinatorTests.catchesUpWhenTheFrontierIsReached` — asserts `.catchingUp` right after `play()` without holding the fake engine; fix: `engine.hold()` before `load`, assert, `engine.release()`, then `waitForRenderIdle()`.
- `PlayerModelTests.transportAndSeeks` — uses the real clock; occasionally trips when run with everything else.

App polish parked for the final Plan 4a pass or Plan 4b:
- Check on the simulator that swipe-to-archive in the Queue list does not fight the pager's horizontal page swipe.
- `ControlPill`'s rate menu passes an empty `systemImage` for non-current rows (console warning); Plan 4b replaces the menu with the speed picker.
- Literal colors inherited from the plan text: white on the accent pill, the mini-player shadow.
- Mini-player stays visible while a document is loaded even if the Queue is empty (spec says hide only when the Queue is empty; harmless).
- `TickScrubber` drag hit area is 22pt tall; thumb may flash back for a frame after a seek.
- `DetailsSheet` uses `.background` rather than `.presentationBackground`.

From Plan 3's final review (deliberately deferred):
- `Library.evictAudio` must only run for a document that is not loaded in the player (or reload it after) because `LibraryStore.saveChapter` overwrites whole chapters. Plan 4b's `StorageModel` does exactly this.
- `LocatorMapping.locator(for:)` defaults the media type to XHTML; PDF positions need `.pdf`.
- `Library.store` is public, so the facade can be bypassed; `Library.delete` is not idempotent.
- PDF: outline traversal is top-level only; `PDFCover` upscales narrow pages.
- `SystemSpeechEngine`: whether `AVSpeechSynthesisMarker.byteSampleOffset` is a byte or sample offset is unverified (macOS compact voices emit no markers); check on a device with a premium voice.

From Plan 2:
- `PlaybackCoordinator.fill()` runs outside its serial chain (a seek during a fill can leave a stale clip); the ~76 ms time-pitch look-ahead is a calibration item (`AudioPlayer.outputLatencySeconds`); `TimeIndex` is rebuilt on every `.rendered` event; a `.failed` event without a `.rendered` leaves `.catchingUp` with no UI escape.

## Working conventions

- Every plan task ends with its own commit using the message given in the plan; tests first, then code.
- Keep `Position` as the only persisted location; never persist utterance indices or Readium types.
- Tokens only in views (no literal colors), one `accent` element per screen, no cards or dividers.
- Run `swift test` and `scripts/build-app.sh` before every commit that touches the app; `scripts/test-readium.sh` when `Packages/T2SReadium` changes.
- Commit trailer used so far: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` on AI-written commits.
