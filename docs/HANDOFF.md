# t2s_reader — hand-off and next steps

_Last updated 2026-09-02 (evening, after Plan 4a merged). Written for whoever picks up the coding next._

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
| `dev` | integration branch, everything below is merged here | Plans 1, 2, 3 and 4a done. 253 root tests + 12 simulator tests green; the app builds and launches on the simulator. Plan 4b document committed. |
| `main` | stale: only the initial spec commit | Not used for integration yet; fast-forward it to `dev` when you want a release point. |

Plan branches are short-lived: each plan runs on its own branch off `dev` (locally in a git
worktree under `.worktrees/`, git-ignored) and is merged and deleted when its final review is clean.

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
- **App/** — the SwiftUI app `T2SReader`: design tokens and type roles (Inter, bundled), composition root, three-page pager with mini-player, Queue page, Collection page + book sheet, player sheet with the tick scrubber, Add sheet (paste a link → WKWebView + Readability.js extraction preview, open a file, paste text), audio session + device monitor. Plan 4a.

## Where things are right now: Plan 4a is on `dev`

Plan file: [2026-09-02-plan-4a-app-shell.md](superpowers/plans/2026-09-02-plan-4a-app-shell.md).
All 12 tasks were executed task by task with a review after each, then a whole-branch review
(`opus`), one fix wave of 17 commits, and a scoped re-review. The branch was merged into `dev`
and deleted.

What the fix wave changed that you should know about:
- **Audio session recovery** (`AudioSessionController`, `AudioPlayer`): interruptions re-activate the
  session on `.ended` and resume when iOS says `.shouldResume`; the engine restarts after a
  configuration change and at `play()`. **Unverified on hardware** — see the device questions below.
- **Scrubber cost**: `ScrubberModel.renderedTicks` is one pass over the timeline and `PlayerModel`
  caches it per `PlaybackCoordinator.timelineRevision`. Rule for the Reader in Plan 4b: anything
  O(timeline) on a model is a stored, invalidated cache, never a computed property.
- **Library refresh**: `LibraryModel.refresh()` decodes only documents whose summary changed and
  never re-processes a stale document (`Library.currentTimeline`); re-derivation happens on load.
- **Import**: the player opens from the Add sheet's `onDismiss`; files opened from other apps go
  through the Add sheet (`RootPager.onOpenURL`); `ImportModel.isBusy` guards re-entry; Inbox copies
  are deleted after a successful import.
- **SystemSpeechEngine**: 60 s watchdog per utterance, no retain cycle per utterance, non-Float32
  voice buffers are converted instead of rejected.
- Sweep: iPhone-only device family, ATS allows arbitrary loads in web content (the link page), the
  extractor's web view uses a non-persistent data store, `docs/licenses.md` lists every third-party
  component.

**Important honesty note:** the app has only been built and launched on the simulator. Nobody has
imported a document through the UI on a device or checked that audio survives a phone call.

## What comes after

1. **Plan 4b (yours)** — Reader page (Readium navigator with the active word decorated, auto-scroll,
   tap-to-seek), speed picker, sleep timer, autoplay-next, Preferences (voices, playback, reading
   appearance, pronunciation dictionary, storage manager), per-document voice change.
   Written, not started: [2026-09-02-plan-4b-reader-controls.md](superpowers/plans/2026-09-02-plan-4b-reader-controls.md).
   Start it on a branch off `dev` (`git checkout -b plan-4b-reader-controls dev`). Plan 4b builds
   on Plan 4a's `PlayerModel`, `AppEnvironment`, tokens and pager; nothing in it conflicts with
   what is on `dev` now.
2. **Plan 0 spikes (device work — this was always meant for you)** —
   [2026-09-02-plan-0-spikes.md](superpowers/plans/2026-09-02-plan-0-spikes.md): the harness under
   `spikes/SpikeHarness/` (xcodegen) with Kokoro via `kokoro-ios`. Spec §7.2 background compute,
   §7.7 `BGProcessingTask`, §7.3/§7.5 runtime and memory, §7.4 word-timing accuracy, §7.1 MisakiSwift
   coverage + the license audit. Findings go in `spikes/findings/`. Plan 5 depends on these results.
   While you have a device in hand, answer these for the app itself:
   - Does a book render end to end on hardware with `SystemSpeechEngine`, and what `commonFormat`
     do the iOS voices deliver (Float32 or Int16)? Word-marker offsets still assume 4-byte samples.
   - Does audio survive a phone call and AirPods in/out (session `.ended`, engine restart)?
   - Does an `http://` link load, and does share-to-app (`onOpenURL`) open the Add sheet?
3. **Plan 5** (not written yet) — Kokoro engine replacing `SystemSpeechEngine`, Share Extension
   (reuses `ArticleExtractor` + `ImportModel`), Now Playing / `MPRemoteCommandCenter` /
   `mediaServicesWereReset` (an explicit audio-lifecycle task — `.longFormAudio` presupposes it),
   multi-document Prepare runner with `BGProcessingTask` (wires `AppPaths.prepareBudgetKey`, which
   is defined and tested but not read yet), BYO-key HTTP engine.
4. **Plan 6** (not written yet) — CloudKit sync behind `SyncProvider`, Live Activity, App Intents, Spotlight.

## Known issues and parked items

From Plan 4a's final review (deliberately deferred):
- No app icon / asset catalog yet — blocking for TestFlight, fine for development.
- CI: the `app-ios` and `readium-ios` jobs use the `macos-26` runner label (unverified), no Xcode
  pin, no SPM cache.
- `Tokens.accentSoft` is unused on purpose: reserved for the read-along word highlight in Plan 4b
  (the Add sheet's pills stay `surface`).
- Deliberate gaps until 4b: the player sheet has no "Read along →" row; file import rows show the
  filename; once an Add-sheet path is chosen there is no way back to the three options except
  dismissing.
- `LibraryModel` progress is still computed per queued document on refresh (cached per summary);
  lazy per-row computation and an explicit, cancellable stale-timeline migration are the next step
  if the library grows large.
- Test temp directories under `t2s-app-<uuid>` are not removed after the suite.
- Check on the simulator that swipe-to-archive in the Queue list does not fight the pager's
  horizontal page swipe. Mini-player stays visible while a document is loaded even if the Queue is
  empty (harmless).

From Plan 3's final review (deliberately deferred):
- `Library.evictAudio` must only run for a document that is not loaded in the player (or reload it after) because `LibraryStore.saveChapter` overwrites whole chapters. Plan 4b's `StorageModel` does exactly this.
- `LocatorMapping.locator(for:)` defaults the media type to XHTML; PDF positions need `.pdf`.
- `Library.store` is public, so the facade can be bypassed; `Library.delete` is not idempotent.
- PDF: outline traversal is top-level only; `PDFCover` upscales narrow pages.
- `SystemSpeechEngine`: whether `AVSpeechSynthesisMarker.byteSampleOffset` is a byte or sample offset is unverified (macOS compact voices emit no markers); the divisor now follows the voice's sample size, but check the timings on a device with a premium voice.

From Plan 2:
- `PlaybackCoordinator.fill()` runs outside its serial chain (a seek during a fill can leave a stale clip); the ~76 ms time-pitch look-ahead is a calibration item (`AudioPlayer.outputLatencySeconds`); `TimeIndex` is rebuilt on every `.rendered` event; a `.failed` event without a `.rendered` leaves `.catchingUp` with no UI escape.

## Working conventions

- Every plan task ends with its own commit using the message given in the plan; tests first, then code.
- Keep `Position` as the only persisted location; never persist utterance indices or Readium types.
- Tokens only in views (no literal colors), one `accent` element per screen, no cards or dividers.
- Run `swift test` and `scripts/build-app.sh` before every commit that touches the app; `scripts/test-readium.sh` when `Packages/T2SReadium` changes.
- Commit trailer used so far: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` on AI-written commits.
